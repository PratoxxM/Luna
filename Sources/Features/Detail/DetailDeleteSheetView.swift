import SwiftUI

struct DetailDeleteSheetView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let target: TvDeleteRequestTarget
    var onPrepareBeforePreflight: (@MainActor () -> Void)? = nil
    let onDeleted: (TvDeleteExecuteResponse) -> Void
    let onCancel: () -> Void

    @State private var preflight: TvDeletePreflightResponse?
    @State private var isLoadingPreflight: Bool = true
    @State private var isDeleting: Bool = false
    @State private var errorMessage: String?

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
                            .font(.title2.weight(.bold))
                            .foregroundStyle(LunaTheme.linen)
                        Text(headerSubtitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(LunaTheme.moonlight)
                            .lineLimit(2)
                    }

                    Spacer()

                    LunaPillButton("Lukk", systemImage: "xmark", prominence: .subtleChip) {
                        onCancel()
                    }
                    .disabled(isDeleting)
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

                if isLoadingPreflight {
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Kontrollerer filer og aktiv avspilling…")
                            .font(.headline)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .padding(.vertical, 28)
                } else if let preflight, !preflight.blockers.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(preflight.blockers) { blocker in
                            HStack(spacing: 14) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3)
                                    .foregroundStyle(LunaTheme.warn)
                                Text(blocker.message)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(LunaTheme.linen)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LunaTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(LunaTheme.warn.opacity(0.45), lineWidth: 1.5)
                            )
                        }

                        LunaPillButton("Forstått", prominence: .glassPill) {
                            onCancel()
                        }
                        .padding(.top, 6)
                    }
                } else if let preflight {
                    let freedText = TvDeleteFilesSummary.formatGigabytesOrMegabytes(bytes: preflight.files.freedDisplayBytes)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 24) {
                            summaryStatBox(
                                title: "Frigjøres på lagring",
                                value: preflight.files.count > 0 ? freedText : "0 GB",
                                accent: preflight.files.freedDisplayBytes > 0 ? LunaTheme.amber : LunaTheme.muted
                            )
                            summaryStatBox(
                                title: "Filer som fjernes",
                                value: "\(preflight.files.count)",
                                accent: LunaTheme.linen
                            )
                        }

                        Text(confirmationDescription(preflight: preflight, freedText: freedText))
                            .font(.callout)
                            .foregroundStyle(LunaTheme.moonlight)
                            .fixedSize(horizontal: false, vertical: true)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LunaTheme.coral)
                        }

                        HStack(spacing: 16) {
                            LunaPillButton(
                                isDeleting ? "Sletter…" : "Bekreft sletting",
                                systemImage: "trash.fill",
                                prominence: .glassPill,
                                accent: .coral
                            ) {
                                Task { await confirmDelete() }
                            }
                            .disabled(isDeleting || preflight.preflightId == nil)

                            LunaPillButton("Avbryt", prominence: .subtleChip) {
                                onCancel()
                            }
                            .disabled(isDeleting)
                        }
                        .padding(.top, 6)
                    }
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(errorMessage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(LunaTheme.coral)

                        HStack(spacing: 14) {
                            LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise", prominence: .glassPill) {
                                Task { await loadPreflight() }
                            }
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
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1.5)
            )
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
            let fileLabel = LunaCopy.plural(preflight.files.count, "mediefil", "mediefiler")
            if target.isWholeTitle {
                return "Dette sletter \(fileLabel) (\(freedText)) permanent fra NAS og fjerner tittelen fra overvåking, huskeliste og lister."
            }
            return "Dette sletter \(fileLabel) (\(freedText)) permanent fra NAS og nullstiller lokal progresjon for utvalget."
        }
        return "Ingen lokale mediefiler er tilknyttet på disk. Bekreft for å rydde opp oppføringen og fjerne den fra lister og overvåking."
    }

    private func summaryStatBox(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(LunaTheme.muted)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LunaTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LunaTheme.warmBorderSubtle, lineWidth: 1)
        )
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
        isDeleting = false
    }
}
