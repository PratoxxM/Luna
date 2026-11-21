import SwiftUI
import AetherBridge

struct SettingsServerDiagnosticsSectionView: View {
    @Environment(AppSessionStore.self) private var sessionStore

    let cacheBytes: Int64
    @Binding var cacheClearedNotice: Bool
    @Binding var showReconnectDialog: Bool
    let onRefreshCacheMetrics: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LunaTokens.Layout.sectionGap) {
            SettingsSectionPanel(title: "Om denne Apple TV-en") {
                LunaInfoRow(
                    title: "App og motor",
                    value: "Luna \(AppSessionStore.currentAppVersionDisplayString()) · AetherEngine \(AetherBridgeInfo.pinnedAetherEngineVersion)"
                )
                LunaListDivider()
                LunaInfoRow(
                    title: "Apple TV-maskinvare",
                    value: "\(DeviceHardwareCapabilities.physicalMemoryGB) GB RAM · Maskinvare-AV1: \(DeviceHardwareCapabilities.supportsHardwareAV1 ? "Støttet" : "Ikke støttet")"
                )
                LunaListDivider()
                LunaInfoRow(
                    title: "LunaCore-server",
                    value: sessionStore.serverBaseURL?.absoluteString ?? "Ikke tilkoblet"
                )
                LunaListDivider()
                LunaInfoRow(title: "Bilde- og kataloghurtigbuffer", value: formattedCacheSize)
            }

            SettingsSectionPanel(title: "Vedlikehold") {
                LunaListRow(
                    title: "Tøm hurtigbuffer",
                    leadingSystemImage: "trash",
                    trailingText: cacheClearedNotice ? "Hurtigbuffer tømt" : nil,
                    trailingTextProminent: cacheClearedNotice,
                    isDestructive: true
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

                LunaListDivider()

                LunaListRow(
                    title: "Koble til på nytt…",
                    leadingSystemImage: "arrow.triangle.2.circlepath",
                    showsChevron: true,
                    isDestructive: true
                ) {
                    showReconnectDialog = true
                }
            }
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
