# AetherEngine (`7.69.0`) — Extracted Host API Reference

Canonical signature reference extracted directly from `Luna`'s `Packages/AetherBridge` and `Sources/` integration. Use these exact signatures when modifying playback, subtitle, audio, or prewarm logic on Linux without local Xcode autocompletion.

---

## 1. SwiftPM Package & Trait Pinning (`Packages/AetherBridge`)

```swift
// Packages/AetherBridge/Package.swift (swift-tools-version: 6.1)
.package(
    url: "https://github.com/superuser404notfound/AetherEngine.git",
    exact: "7.69.0",
    traits: [
        "TrueHDObjectAudio",
        "DTSXObjectAudio",
        "DualLayerDolbyVision",
        "DolbyVisionFelCurves",
        "DolbyVisionStillReshaping",
    ]
)

// Packages/AetherBridge/Sources/AetherBridge/Exports.swift
@_exported import AetherEngine

public enum AetherBridgeInfo {
    public static let pinnedAetherEngineVersion = "7.69.0"
}
```

---

## 2. `AetherEngine` Singleton Lifecycle, Properties & Methods

`Luna` owns a single `@MainActor` `AetherEngine` instance across the app lifetime (`Sources/App/LunaApp.swift`).

```swift
@MainActor
public final class AetherEngine: ObservableObject {
    public init() throws

    // Static Prewarm & Display Capabilities
    public static var displayCapabilities: DisplayCapabilities { get }
    @discardableResult
    public static func prewarmDualLayerDolbyVision() async -> Bool
    public static func isPrewarmed(url: URL) -> Bool
    @discardableResult
    public static func prewarm(
        url: URL,
        httpHeaders: [String: String],
        byteBudget: Int
    ) async -> Bool
    public static func discardPrewarmedSources()

    // Subtitle Window & Session Ownership Configuration
    public var maximumSubtitleAdvanceSeconds: Double // Set to 0 to prevent 2nd parallel 4K HTTP stream
    public var maximumSubtitleDelaySeconds: Double   // Set to 10 for positive subtitle delay history
    public var ownsSoftwareNowPlaying: Bool
    public var ownsVideoNowPlayingSession: Bool
    public var ownsVideoNowPlayingCommands: Bool
    public var deactivatesAudioSessionOnStop: Bool   // false in Luna to avoid AVR HDMI blink on exit

    // Published Transport, Format & Track State
    @Published public private(set) var state: PlaybackState
    @Published public private(set) var playbackPhase: PlaybackPhase
    @Published public private(set) var hasFirstFrameReadyForDisplay: Bool
    @Published public private(set) var isAwaitingDisplaySwitch: Bool
    @Published public private(set) var startupProgress: StartupProgress?
    @Published public private(set) var duration: Double
    public var currentTime: Double { get }
    public var bufferedPosition: Double { get }
    public var needsForegroundVideoRestore: Bool { get }

    @Published public private(set) var videoFormat: VideoFormat
    @Published public private(set) var sourceDVProfile: Int?
    @Published public private(set) var dolbyVisionConversion: DolbyVisionConversion?
    @Published public private(set) var videoRoute: VideoRoute
    @Published public private(set) var audioDelivery: AudioDelivery
    @Published public private(set) var sourceVideoCodecName: String?
    @Published public private(set) var sourceVideoWidth: Int32
    @Published public private(set) var sourceVideoHeight: Int32
    @Published public private(set) var sourceVideoFrameRate: Double?
    @Published public private(set) var activeVideoDecoder: String?
    @Published public private(set) var activeAudioDecoder: String?

    @Published public private(set) var mediaChapters: [ChapterInfo]
    @Published public private(set) var audioTracks: [TrackInfo]
    @Published public private(set) var activeAudioTrackIndex: Int?
    @Published public private(set) var subtitleTracks: [TrackInfo]
    @Published public private(set) var activeSubtitleTrackIndex: Int?
    @Published public private(set) var subtitleCues: [SubtitleCue]
    public var softwareSubtitleDelaySeconds: Double { get }

    // Isolated High-Frequency Sub-Objects (Observe ONLY in Leaf Views!)
    public let clock: EngineClock
    public let diagnostics: EngineDiagnostics

    // Scrub Preview Capabilities & Generation
    public var scrubPreviewDrawsInView: Bool { get }
    public var supportsCacheBackedStills: Bool { get }
    public func scrubThumbnail(atSeconds: Double, maxWidth: Int) async -> CGImage?
    @discardableResult
    public func showScrubPreview(atSeconds: Double, in view: AetherScrubPreviewView) async -> Bool

    // Load, Reload & Transport Controls
    @discardableResult
    public func load(
        url: URL,
        startPosition: Double?,
        options: LoadOptions
    ) async throws -> LoadResult
    public func reloadAtCurrentPosition(_ mutateOptions: (inout LoadOptions) -> Void) async throws
    public func prepareForItemReplacement()
    public func play()
    public func pause()
    public func togglePlayPause()
    public func seek(to seconds: Double, exact: Bool) async
    public func stop(resetDisplayCriteria: Bool, finalTeardown: Bool = false)

    // Live Track, Delay & Audio Shaping Controls
    public func selectAudioTrack(index: Int)
    public func setAudioDelay(_ seconds: Double)
    public func setAudioShaping(_ shaping: AudioShaping)
    public func selectSubtitleTrack(index: Int)
    public func clearSubtitle()
    public func setSoftwareSubtitleDelay(_ seconds: Double)
}
```

---

## 3. Leaf Clock & Telemetry Publishers (`clock` & `diagnostics`)

```swift
@MainActor
public final class EngineClock: ObservableObject {
    @Published public private(set) var currentTime: Double       // Observed in PlayerBottomBarView leaf views
    @Published public private(set) var sourceTime: Double        // Observed in SubtitleOverlayView
    @Published public private(set) var bufferedPosition: Double  // Observed in TimelineScrubberLeafView
}

@MainActor
public final class EngineDiagnostics: ObservableObject {
    @Published public private(set) var liveTelemetry: LiveTelemetry?       // 1 Hz — NerdHUDView only
    @Published public private(set) var sessionCacheStatus: SessionCacheStatus
}

public struct StartupProgress: Sendable {
    public let fraction: Double
}

public struct DisplayCapabilities: Sendable {
    public let supportsDolbyVision: Bool
    public let supportsHDR10: Bool
    public let supportsHLG: Bool
}

public struct LiveTelemetry: Sendable {
    public let observedFps: Double?
    public let droppedFrameCount: Int
    public let instantBitrateMbps: Double?
    public let averageBitrateMbps: Double?
    public let networkThroughputMbps: Double?
    public let forwardBufferSeconds: Double?
    public let readerWindowAheadBytes: Int64?
    public let rssMb: Int
    public let objectAudio: ObjectAudioTelemetry?
}

public struct ObjectAudioTelemetry: Sendable {
    public let layout: SpatialSpeakerLayout
    public let activeObjects: Int
    public let objects: Int
    public let elevatedObjects: Int
}

public struct SessionCacheStatus: Equatable, Sendable {
    public static let inactive: SessionCacheStatus
    public let currentForwardBytes: Int64
}
```

---

## 4. `LoadOptions`, Audio Shaping & Enums

```swift
public struct LoadOptions: Sendable {
    public init()
    public var autoplay: Bool
    public var httpHeaders: [String: String]
    public var preferDualLayerDolbyVision: Bool
    public var foldsDolbyVisionFEL: Bool
    public var dolbyVisionHandling: DolbyVisionHandling       // .automatic | .baseLayerOnly
    public var dualLayerRoute: DualLayerRoute                 // .softwareHost | .avPlayerOutput
    public var matchContentEnabled: Bool
    public var displayCriteriaOwner: DisplayCriteriaOwner     // .engine
    public var attemptsHDRMasterOnUnprovenPanel: Bool
    public var panelPresentsDolbyVision: Bool
    public var panelIsInHDRMode: Bool
    public var audioBridgeMode: AudioBridgeMode               // .surroundCompat | .lossless
    public var audioDelaySeconds: Double
    public var audioShaping: AudioShaping
    public var objectAudioRendering: ObjectAudioRendering     // .off | .render(SpatialSpeakerLayout) | .apac(...) | .lpcm(...)
    public var preferredAudioLanguages: [String]
    public var preferredSubtitleLanguages: [String]
    public var skipsContainerAttachments: Bool
    public var generatesBackgroundScrubPreviews: Bool
    public var serveIFramePlaylist: Bool
    public var confirmAtmos: Bool
    public var maxConcurrentSourceRequests: Int
    public var declaredDurationSeconds: Double?
    public var upscalesLowResolutionVideo: Bool
    public var upscaleScaler: UpscaleScaler                   // .automatic | .lineArt
    public var externalSubtitles: [ExternalSubtitleTrack]
}

public struct ExternalSubtitleTrack: Sendable {
    public init(
        url: URL,
        name: String?,
        language: String?,
        isForced: Bool,
        isHearingImpaired: Bool,
        isDefault: Bool,
        httpHeaders: [String: String],
        formatHint: String
    )
}

public struct AudioShaping: Equatable, Sendable {
    public init(
        maxChannels: Int?,
        dialogueGainDB: Double,
        compressor: AudioCompressorPreset?, // .night | nil
        loudnessTargetLUFS: Double?,
        lfeMixDB: Double?
    )
}

public enum SpatialSpeakerLayout: String, Sendable {
    case l512 = "5.1.2"
    case l514 = "5.1.4"
    case l712 = "7.1.2"
    case l714 = "7.1.4"
    case l916 = "9.1.6"
}

public enum PlaybackState: Equatable, Sendable {
    case idle, loading, playing, paused, seeking, ended
}

public enum PlaybackPhase: Equatable, Sendable {
    case idle, loading, playing, paused, seeking, rebuffering, stalled, ended
    case error(String)
}

public enum VideoFormat: Equatable, Sendable {
    case sdr, hdr10, hdr10Plus, hlg, dolbyVision
}

public enum DolbyVisionConversion: Equatable, Sendable {
    case profile7ToProfile81
}

public enum VideoRoute: String, Equatable, Sendable {
    case none, loopback, remoteBypass, software, audio
}

public enum AudioDelivery: String, Equatable, Sendable {
    case none, bridged // additional engine-internal cases exposed via rawValue: String
}
```

---

## 5. Tracks, Chapters, Subtitle Cues, Views & Security Utilities

```swift
public struct TrackInfo: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let codec: String
    public let profile: String?
    public let language: String?
    public let channelLayout: String?
    public let channels: Int32
    public let isAtmos: Bool
    public let isDTSX: Bool
    public let isForced: Bool
    public let isHearingImpaired: Bool
    public let isCommentary: Bool
    public let isExternal: Bool
    public let isDefault: Bool
    public let isNativelyRenderedSubtitle: Bool
}

public struct ChapterInfo: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let startSeconds: Double
    public let durationSeconds: Double
}

public struct SubtitleCue: Identifiable, Sendable {
    public let id: String
    public let startTime: Double
    public let endTime: Double
    public let placement: SubtitleTextPlacement?
    public let body: SubtitleCueBody // .text(String) | .richText([SubtitleTextRun]) | .image(SubtitleBitmap)
}

public struct SubtitleTextPlacement: Sendable {
    public let alignment: Int?     // ASS numpad 1...9
    public let position: CGPoint?  // Normalized 0...1
}

public struct SubtitleTextRun: Sendable {
    public let text: String
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderlined: Bool
    public let isStruckThrough: Bool
    public let color: (r: UInt8, g: UInt8, b: UInt8)?
}

// SwiftUI & UIKit Render Surfaces
public struct AetherPlayerSurface: View {
    public init(engine: AetherEngine)
}

@MainActor
public final class AetherScrubPreviewView: UIView {
    public init()
    public var videoGravity: AVLayerVideoGravity
    public func clear()
}

// Secret Redaction & LAN TLS Trust Hooks
public enum EngineLog {
    @discardableResult public static func registerSecret(_ secret: String) -> Bool
    public static func unregisterSecret(_ secret: String)
}

public enum EngineTLS {
    public static var serverTrustEvaluator: (@Sendable (URLProtectionSpace) -> Bool)?
}
```

---

## 6. Luna Host Abstractions (`Sources/Features/Player/` & `Sources/Core/Playback/`)

- **tvOS Player Transport Seam (`Sources/Features/Player/PlayerTransportProtocol.swift`)**:
  - `@MainActor protocol PlayerTransportControlling`: `state`, `playbackPhase`, `videoRoute`, `currentTime`, `needsForegroundVideoRestore`, `play()`, `pause()`, `togglePlayPause()`, `seek(to:exact:)`, `stop(resetDisplayCriteria:finalTeardown:)`.
  - `protocol NativeAudioActivating: Sendable`: `activateNativePlaybackIfNeeded(videoRoute:) async`.
- **Linux-Testable Core Seam (`Sources/Core/Playback/PlaybackCoreAbstractions.swift`)**:
  - `public protocol PlaybackEngine: AnyObject, Sendable` & `public protocol IOReader: Sendable`, coordinated by `PlaybackCoordinatorStateMachine` and `PlaybackCurtainWatchdog`.
