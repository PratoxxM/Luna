import SwiftUI

struct DetailDeleteSheetView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

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
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 16) {
                    Image(systemName: "trash.circle.fill")
                        .font(LunaTheme.Font.sheetHeaderIcon)
                        .foregroundStyle(LunaTheme.coral)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(target.dialogHeading)
                            .font(LunaTheme.Font.pageTitle)
                            .foregroundStyle(LunaTheme.linen)
                        Text(headerSubtitle)
                            .font(LunaTheme.Font.subtitle)
                            .foregroundStyle(LunaTheme.moonlight)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

                if isLoadingPreflight {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Kontrollerer filer og aktiv avspilling…")
                            .font(LunaTheme.Font.cardTitle)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.vertical, 28)
                } else if let preflight, !preflight.blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(preflight.blockers) { blocker in
                            HStack(spacing: 14) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(LunaTheme.Font.cardTitle)
                                    .foregroundStyle(LunaTheme.warn)
                                Text(blocker.message)
                                    .font(LunaTheme.Font.body)
                                    .foregroundStyle(LunaTheme.linen)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LunaTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: LunaTokens.Radius.poster, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: LunaTokens.Radius.poster, style: .continuous)
                                    .strokeBorder(LunaTheme.warn.opacity(0.45), lineWidth: 1.5)
                            )
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
                        HStack(spacing: 24) {
                            summaryStatBox(
                                title: "Frigjøres på lagring",
                                value: preflight.files.count > 0 ? freedText : "0 GB",
                                accent: LunaTheme.linen
                            )
                            summaryStatBox(
                                title: "Filer som fjernes",
                                value: "\(preflight.files.count)",
                                accent: LunaTheme.linen
                            )
                        }

                        Text(confirmationDescription(preflight: preflight, freedText: freedText))
                            .font(LunaTheme.Font.body)
                            .foregroundStyle(LunaTheme.moonlight)
                            .fixedSize(horizontal: false, vertical: true)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(LunaTheme.Font.subtitle)
                                .foregroundStyle(LunaTheme.coral)
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
                                prominence: .subtleChip,
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
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .font(LunaTheme.Font.body)
                            .foregroundStyle(LunaTheme.coral)

                        HStack(spacing: 14) {
                            LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise", prominence: .glassPill) {
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

                Spacer(minLength: 0)
            }
            .padding(44)
            .frame(maxWidth: 920)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .lunaTopLightEdge(
                cornerRadius: LunaTokens.Radius.panel,
                topColor: LunaTokens.Edge.top3,
                sideColor: LunaTokens.Edge.top1
            )
            .defaultFocus($focusedControl, .cancel, priority: .userInitiated)
            .focusScope(deleteFocusNamespace)
        }
        .onChange(of: isLoadingPreflight) { _, loading in
            if !loading {
                focusedControl = .cancel
            }
        }
        .onExitCommand {
            if !isDeleting {
                onCancel()
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

    private func summaryStatBox(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LunaTheme.Font.caption)
                .foregroundStyle(LunaTheme.muted)
            Text(value)
                .font(LunaTheme.Font.cardTitle.monospacedDigit())
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LunaTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: LunaTokens.Radius.poster, style: .continuous))
        .lunaTopLightEdge(cornerRadius: LunaTokens.Radius.poster)
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
