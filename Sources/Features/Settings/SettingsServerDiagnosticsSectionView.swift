import SwiftUI
import AetherBridge

struct SettingsServerDiagnosticsSectionView: View {
    @Environment(AppSessionStore.self) private var sessionStore

    let cacheBytes: Int64
    @Binding var cacheClearedNotice: Bool
    @Binding var showReconnectDialog: Bool
    let onRefreshCacheMetrics: () async -> Void
    @State private var isEditingFallbackURL: Bool = false
    @State private var fallbackURLDraft: String = ""

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
                if let localURL = sessionStore.serverLocalHostnameURL,
                   localURL != sessionStore.serverBaseURL {
                    LunaListDivider()
                    LunaInfoRow(
                        title: "Lokalt mDNS-vertsnavn",
                        value: localURL.absoluteString
                    )
                }
                LunaListDivider()
                LunaListRow(
                    title: "Sekundær serveradresse (fallback)",
                    subtitle: sessionStore.fallbackServerURL?.absoluteString ?? "Brukes kun dersom primærserver ikke svarer",
                    leadingSystemImage: "network"
                ) {
                    fallbackURLDraft = sessionStore.fallbackServerURL?.absoluteString ?? ""
                    isEditingFallbackURL.toggle()
                }
                if isEditingFallbackURL {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("f.eks. https://lunacore.local:8920", text: $fallbackURLDraft)
                            .frame(maxWidth: 680)
                        HStack(spacing: 12) {
                            LunaPillButton("Lagre", prominence: .primary, size: .compact) {
                                sessionStore.setFallbackServerURL(fallbackURLDraft)
                                isEditingFallbackURL = false
                            }
                            if sessionStore.fallbackServerURL != nil {
                                LunaPillButton("Fjern", prominence: .glassPill, size: .compact) {
                                    sessionStore.setFallbackServerURL(nil)
                                    fallbackURLDraft = ""
                                    isEditingFallbackURL = false
                                }
                            }
                            LunaPillButton("Avbryt", prominence: .subtleChip, size: .compact) {
                                isEditingFallbackURL = false
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
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
                        ItemDetailMemoryCache.shared.clear()
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
