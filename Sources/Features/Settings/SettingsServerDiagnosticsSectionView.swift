import SwiftUI
import AetherBridge

struct SettingsServerDiagnosticsSectionView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let cacheBytes: Int64
    @Binding var cacheClearedNotice: Bool
    @Binding var showUnpairConfirm: Bool
    @Binding var showResetConfirm: Bool
    let onRefreshCacheMetrics: () async -> Void

    var body: some View {
        SettingsSectionPanel(title: "System") {
            SettingsInfoRow(
                title: "App-versjon",
                value: "Luna \(AppSessionStore.currentAppVersionDisplayString())"
            )
            SettingsSectionDivider()
            SettingsInfoRow(
                title: "LunaCore-server",
                value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet"
            )
            SettingsSectionDivider()
            SettingsInfoRow(
                title: "Aktivt rom",
                value: "\(sessionStore.roomName) (\(sessionStore.effectiveHardwareProfile))"
            )
            SettingsSectionDivider()
            SettingsInfoRow(title: "Bilde- og kataloghurtigbuffer", value: formattedCacheSize)
            SettingsSectionDivider()

            SettingsToggleRowButton(
                title: "Tillat selvsignert TLS-sertifikat på lokalnett",
                isOn: $sessionStore.allowSelfSignedLanTLS
            )

            SettingsSectionDivider()

            HStack(spacing: 12) {
                LunaPillButton(
                    "Tøm hurtigbuffer",
                    systemImage: "trash",
                    prominence: .subtleChip,
                    accent: .coral,
                    size: .compact
                ) {
                    Task {
                        CatalogBrowseMemoryCache.shared.clear()
                        LibraryBrowseMemoryCache.shared.clear()
                        await DiskSWRStore.clearAllAsync()
                        await ArtworkPipeline.shared.clearAll()
                        AetherEngine.discardPrewarmedSources()
                        sessionStore.notifyContentMutated()
                        await onRefreshCacheMetrics()
                        cacheClearedNotice = true
                    }
                }

                LunaPillButton(
                    "Par TV på nytt",
                    systemImage: "qrcode",
                    prominence: .subtleChip,
                    accent: .coral,
                    size: .compact
                ) {
                    showUnpairConfirm = true
                }

                LunaPillButton(
                    "Nullstill tilkobling",
                    systemImage: "xmark.circle",
                    prominence: .subtleChip,
                    accent: .coral,
                    size: .compact
                ) {
                    showResetConfirm = true
                }

                Spacer(minLength: 0)

                if cacheClearedNotice {
                    Text("Hurtigbuffer tømt")
                        .font(LunaTheme.Font.settingsStatusTag)
                        .foregroundStyle(LunaTheme.amber)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.top, 2)
        }
    }

    private var formattedCacheSize: String {
        if cacheBytes <= 0 {
            return "0 MB"
        }
        let mb = Double(cacheBytes) / 1_048_576.0
        return LunaCopy.formatMegabytes(mb, decimals: 1)
    }
}
