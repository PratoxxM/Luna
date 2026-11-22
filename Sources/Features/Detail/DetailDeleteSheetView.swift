import SwiftUI

struct DetailDeleteSheetView: View {
    @Environment(AppSessionStore.self) private var sessionStore

    private enum DeleteSheetFocus: Hashable {
        case cancel
        case confirm
    }

    let target: TvDeleteRequestTarget
    var onPrepareBeforePreflight: (@MainActor () -> Void)? = nil
    let onDeleted: (TvDeleteExecuteResponse) -> Void
    let onCancel: () -> Void

    @State private var preflight: TvDeletePreflightResponse?
    @State private var isLoadingPreflight: Bool = true
    @State private var isDeleting: Bool = false
    @State private var errorMessage: String?
    @FocusState private var focusedControl: DeleteSheetFocus?
    @Namespace private var deleteFocusNamespace

    var body: some View {
        LunaSheetContainer(
            title: target.dialogHeading,
            subtitle: headerSubtitle,
            width: .narrow,
            onClose: {
                if !isDeleting {
                    onCancel()
                }
            }
        ) {
            VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                if isLoadingPreflight {
                    LunaLoadingRow(message: "Kontrollerer filer og aktiv avspilling…")
                } else if let preflight, !preflight.blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(preflight.blockers) { blocker in
                            HStack(alignment: .center, spacing: 12) {
                                Circle()
                                    .fill(LunaTheme.warn)
                                    .frame(width: 8, height: 8)
                                Text(blocker.message)
                                    .font(LunaTheme.Font.body)
                                    .foregroundStyle(LunaTheme.linen)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        LunaPillButton("Forstått", prominence: .glassPill) {
                            onCancel()
                        }
                        .focused($focusedControl, equals: .cancel)
                        .prefersDefaultFocus(true, in: deleteFocusNamespace)
                        .padding(.top, 6)
                    }
                } else if let preflight {
                    let freedText = TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: preflight.files.freedDisplayBytes)
                    VStack(alignment: .leading, spacing: 18) {
                        LunaListGroup(showsSurface: false) {
                            LunaInfoRow(
                                title: "Frigjøres på lagring",
                                value: preflight.files.count > 0 ? freedText : "0 GB"
                            )
                            LunaListDivider()
                            LunaInfoRow(
                                title: "Filer som fjernes",
                                value: "\(preflight.files.count)"
                            )
                        }

                        Text(confirmationDescription(preflight: preflight, freedText: freedText))
                            .font(LunaTheme.Font.body)
                            .foregroundStyle(LunaTheme.moonlight)
                            .fixedSize(horizontal: false, vertical: true)

                        if let errorMessage {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(LunaTheme.coral)
                                    .frame(width: 8, height: 8)
                                Text(errorMessage)
                                    .font(LunaTheme.Font.subtitle)
                                    .foregroundStyle(LunaTheme.linen)
                            }
                        }

                        HStack(spacing: 16) {
                            LunaPillButton("Avbryt", prominence: .glassPill) {
                                onCancel()
                            }
                            .disabled(isDeleting)
                            .focused($focusedControl, equals: .cancel)
                            .prefersDefaultFocus(true, in: deleteFocusNamespace)

                            LunaPillButton(
                                isDeleting ? "Sletter…" : "Bekreft sletting",
                                systemImage: "trash.fill",
                                prominence: .glassPill,
                                accent: .coral
                            ) {
                                Task { await confirmDelete() }
                            }
                            .disabled(isDeleting || preflight.preflightId == nil)
                            .focused($focusedControl, equals: .confirm)
                        }
                        .padding(.top, 6)
                    }
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 16) {
                        LunaInlineError(message: errorMessage) {
                            Task { await loadPreflight() }
                        }
                        .focused($focusedControl, equals: .cancel)
                        .prefersDefaultFocus(true, in: deleteFocusNamespace)

                        LunaPillButton("Avbryt", prominence: .subtleChip) {
                            onCancel()
                        }
                    }
                }
            }
            .defaultFocus($focusedControl, .cancel, priority: .userInitiated)
            .focusScope(deleteFocusNamespace)
        }
        .onChange(of: isLoadingPreflight) { _, loading in
            if !loading {
                focusedControl = .cancel
            }
        }
        .task {
            await loadPreflight()
        }
    }

    private var headerSubtitle: String {
        if let sub = target.subtitle, !sub.isEmpty {
            return "\(target.title) · \(sub)"
        }
        return target.title
    }

    private func confirmationDescription(preflight: TvDeletePreflightResponse, freedText: String) -> String {
        if preflight.files.count > 0 {
            let fileLabel = LunaCopy.mediaFilesCount(preflight.files.count)
            if target.isWholeTitle {
                return "Dette sletter \(fileLabel) (\(freedText)) permanent fra lagring og fjerner tittelen fra overvåking, huskeliste og lister."
            }
            return "Dette sletter \(fileLabel) (\(freedText)) permanent fra lagring og nullstiller lokal progresjon for utvalget."
        }
        return "Ingen lokale mediefiler er tilknyttet på disk. Bekreft for å rydde opp oppføringen og fjerne den fra lister og overvåking."
    }

    private func loadPreflight() async {
        onPrepareBeforePreflight?()
        guard let client = sessionStore.makeClient() else {
            errorMessage = "Ikke tilkoblet LunaCore."
            isLoadingPreflight = false
            return
        }
        isLoadingPreflight = true
        errorMessage = nil
        do {
            preflight = try await client.deletePreflight(target: target)
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }
        isLoadingPreflight = false
    }

    private func confirmDelete() async {
        guard !isDeleting,
              let preflightId = preflight?.preflightId,
              let client = sessionStore.makeClient() else { return }
        onPrepareBeforePreflight?()
        isDeleting = true
        errorMessage = nil
        do {
            let result = try await client.executeDelete(
                target: target,
                preflightId: preflightId,
                removeFromLibrary: target.isWholeTitle
            )
            ItemDetailMemoryCache.invalidate(itemId: target.itemId, tmdbId: target.tmdbId)
            sessionStore.notifyContentMutated()
            onDeleted(result)
        } catch LunaCoreError.unauthorized {
            sessionStore.unpairDevice()
        } catch {
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }
        isDeleting = false
    }
}
