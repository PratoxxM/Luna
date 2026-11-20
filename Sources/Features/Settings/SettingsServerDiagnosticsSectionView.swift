import SwiftUI
import AetherBridge

struct SettingsServerDiagnosticsSectionView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let cacheBytes: Int64
    @Binding var cacheClearedNotice: Bool
    @Binding var showReconnectDialog: Bool
    let onRefreshCacheMetrics: () async -> Void

    var body: some View {
        SettingsSectionPanel(title: "System") {
            SettingsInfoRow(
                title: "App og motor",
                value: "Luna \(AppSessionStore.currentAppVersionDisplayString()) · AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion)"
            )
            SettingsSectionDivider()
            SettingsInfoRow(
                title: "Apple TV-maskinvare",
                value: "\(DeviceHardwareCapabilities.physicalMemoryGB) GB RAM · Maskinvare-AV1: \(DeviceHardwareCapabilities.supportsHardwareAV1 ? "Støttet" : "Ikke støttet")"
            )
            SettingsSectionDivider()
            SettingsInfoRow(
                title: "LunaCore-server",
                value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet"
            )
            SettingsSectionDivider()
            SettingsInfoRow(
                title: "Aktivt rom",
                value: "\(sessionStore.roomName) · \(sessionStore.effectiveEquipmentLabel)"
            )
            SettingsSectionDivider()
            SettingsInfoRow(title: "Bilde- og kataloghurtigbuffer", value: formattedCacheSize)
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
                        AetherEngine.discardRetainedSessionCache()
                        sessionStore.notifyContentMutated()
                        await onRefreshCacheMetrics()
                        cacheClearedNotice = true
                    }
                }

                LunaPillButton(
                    "Koble til på nytt…",
                    systemImage: "arrow.triangle.2.circlepath",
                    prominence: .subtleChip,
                    accent: .coral,
                    size: .compact
                ) {
                    showReconnectDialog = true
                }

                Spacer(minLength: 0)

                if cacheClearedNotice {
                    Text("Hurtigbuffer tømt")
                        .font(LunaTheme.Font.settingsStatusTag)
                        .foregroundStyle(LunaTheme.emerald)
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
