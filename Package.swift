// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LunaCore",
    platforms: [
        .tvOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "LunaCore",
            targets: ["LunaCore"]
        ),
    ],
    targets: [
        .target(
            name: "LunaCore",
            path: "Sources",
            exclude: [
                "App/LunaApp.swift",
                "App/LunaNavigationBarVisibility.swift",
                "App/LunaTopBarView.swift",
                "App/MainNavigationShell.swift",
                "App/PreviewMockFixtures.swift",
                "App/PreviewMockURLProtocol.swift",
                "Features",
                "Core/Cache/ArtworkPipeline.swift",
                "Core/Cache/BlurHashDecoder.swift",
                "Core/Config/ComfortPreferences.swift",
                "Core/Config/ServerConfiguration.swift",
                "Core/Discovery",
                "DesignSystem/AmbientBackdropView.swift",
                "DesignSystem/CachedArtworkView.swift",
                "DesignSystem/Cards",
                "DesignSystem/LunaBadges.swift",
                "DesignSystem/LunaCrescentMarkView.swift",
                "DesignSystem/LunaFocusStyle.swift",
                "DesignSystem/LunaInlineStateViews.swift",
                "DesignSystem/LunaListRow.swift",
                "DesignSystem/LunaPillButton.swift",
                "DesignSystem/LunaSheetContainer.swift",
                "DesignSystem/LunaTheme.swift",
                "DesignSystem/LunaThemeTypography.swift",
                "DesignSystem/Tokens",
            ],
            sources: [
                "App/PreviewLaunchConfiguration.swift",
                "Core/Cache/DiskSWRStore.swift",
                "Core/Cache/InflightTaskCoalescer.swift",
                "Core/Catalog/CatalogShelfIndexer.swift",
                "Core/Config/DeviceHardwareCapabilities.swift",
                "Core/Config/SideloadSafeStorage.swift",
                "Core/Config/SmartTrackRuleEngine.swift",
                "Core/Models/ChapterModels.swift",
                "Core/Models/DetailModels.swift",
                "Core/Models/EpisodeTitleFormatter.swift",
                "Core/Models/HomeModels.swift",
                "Core/Models/PlaybackDrawerModels.swift",
                "Core/Models/PlaybackModels.swift",
                "Core/Models/TvDeletionModels.swift",
                "Core/Networking/LunaCoreClient+HomeCatalog.swift",
                "Core/Networking/LunaCoreClient+LibraryDetail.swift",
                "Core/Networking/LunaCoreClient+Playback.swift",
                "Core/Networking/LunaCoreHTTPTransport.swift",
                "Core/Networking/LunaCoreSessionPool.swift",
                "Core/Networking/PlaybackResolveSocket.swift",
                "Core/Playback/PlaybackCoreAbstractions.swift",
                "Core/Playback/PlaybackTrackIntent.swift",
                "Core/Playback/PlayerTimelinePolicy.swift",
                "Core/Playback/RemoteScrubMath.swift",
                "DesignSystem/LunaCopy.swift",
            ]
        ),
        .testTarget(
            name: "LunaCoreTests",
            dependencies: ["LunaCore"],
            path: "Tests/LunaCoreTests"
        ),
    ]
)
