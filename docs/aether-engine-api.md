# AetherEngine (`7.75.0`) — Extracted Host API Reference

Canonical signature reference extracted directly from `Luna`'s `Packages/AetherBridge` and `Sources/` integration. Use these exact signatures when modifying playback, subtitle, audio, or prewarm logic on Linux without local Xcode autocompletion.

---

## 1. SwiftPM Package & Trait Pinning (`Packages/AetherBridge`)

```swift
// Packages/AetherBridge/Package.swift (swift-tools-version: 6.2)
.package(
    url: "https://github.com/superuser404notfound/AetherEngine.git",
    exact: "7.75.0",
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
    public static let pinnedAetherEngineVersion = "7.75.0"
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
    public nonisolated static func prewarmDualLayerDolbyVision() async -> Bool
    public nonisolated static func isPrewarmed(url: URL) -> Bool
    @discardableResult
    public nonisolated static func prewarm(
        url: URL,
        httpHeaders: [String: String] = [:],
        byteBudget: Int? = nil
    ) async -> SourcePrewarmReport
    public nonisolated static func discardPrewarmedSources()
    public nonisolated static func discardRetainedSessionCache()
    public nonisolated static var retainedSessionCacheBytes: Int { get }

    // Subtitle Window, Audio Session & Now Playing Configuration
    public var maximumSubtitleAdvanceSeconds: Double // Set to 0 to prevent 2nd parallel 4K HTTP stream
    public var maximumSubtitleDelaySeconds: Double   // Set to 10 for positive subtitle delay history
    public var heldPictureFrameWaitSeconds: Double
    public var nativeAudioSessionActivationEnabled: Bool // default false; opt-in for bare AVPlayerLayer hosts
    public var ownsSoftwareNowPlaying: Bool
    public var ownsVideoNowPlayingSession: Bool
    public var ownsVideoNowPlayingCommands: Bool
    public var deactivatesAudioSessionOnStop: Bool   // false in Luna to avoid AVR HDMI blink on exit

    // Published Transport, Format & Track State
    @Published public private(set) var state: PlaybackState
    @Published public internal(set) var errorInfo: PlaybackErrorInfo?
    @Published public private(set) var playbackPhase: PlaybackPhase
    @Published public private(set) var hasFirstFrameReadyForDisplay: Bool
    @Published public private(set) var isAwaitingDisplaySwitch: Bool
    @Published public private(set) var startupProgress: StartupProgress?
    @Published public private(set) var activeUpscale: UpscaleStatus?
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
    @Published public private(set) var fontAttachments: [FontAttachment]
    public var softwareSubtitleDelaySeconds: Double { get }

    // Isolated High-Frequency Sub-Objects (Observe ONLY in Leaf Views!)
    public let clock: PlaybackClock
    public let diagnostics: EngineDiagnostics
    public let systemCaptionRequest: PassthroughSubject<SystemCaptionRequest, Never>

    // Scrub Preview Capabilities & Generation
    public var scrubPreviewDrawsInView: Bool { get }
    public var supportsCacheBackedStills: Bool { get }
    public func scrubThumbnail(atSeconds seconds: Double, maxWidth: Int = 320) async -> CGImage?
    @discardableResult
    public func showScrubPreview(atSeconds seconds: Double, in view: AetherScrubPreviewView) async -> ScrubPreviewPlacement?

    // Load, Reload, Held Outgoing Picture & Transport Controls
    @discardableResult
    public func load(
        url: URL,
        startPosition: Double? = nil,
        options: LoadOptions = .init(),
        audioSourceStreamIndex: Int32? = nil,
        discTitleID: Int? = nil
    ) async throws -> SourceProbe?
    @discardableResult
    public func reloadAtCurrentPosition(
        applying change: (inout LoadOptions) -> Void
    ) async throws -> SessionOptionCorrectionOutcome
    public func prepareForItemReplacement()
    @discardableResult
    public func holdOutgoingPicture(on view: AetherStillView) async -> Bool
    public func releaseOutgoingPicture()
    public func play()
    public func pause()
    public func togglePlayPause()
    public func seek(to seconds: Double) async
    public func seek(to seconds: Double, exact: Bool) async
    public func stop(resetDisplayCriteria: Bool = true, finalTeardown: Bool? = nil)

    // Live Track, Delay & Audio Shaping Controls
    public func selectAudioTrack(index: Int)
    public func setAudioDelay(_ seconds: Double)
    public func setAudioShaping(_ shaping: AudioShaping)
    public func selectSubtitleTrack(index: Int)
    public func clearSubtitle()
    public func setSoftwareSubtitleDelay(_ seconds: Double)

    // Now Playing System Controls
    public func setVideoNowPlayingInfo(_ info: [String: Any])
    public func setNowPlayingTrackCommands(next: (@MainActor () -> Void)?, previous: (@MainActor () -> Void)?)
}
```

---

## 3. Leaf Clock & Telemetry Publishers (`clock` & `diagnostics`)

```swift
@MainActor
public final class PlaybackClock: ObservableObject {
    @Published public internal(set) var currentTime: Double       // Observed in PlayerBottomBarView leaf views
    @Published public internal(set) var sourceTime: Double        // Observed in SubtitleOverlayView
    @Published public internal(set) var bufferedPosition: Double  // Observed in TimelineScrubberLeafView
}

@MainActor
public final class EngineDiagnostics: ObservableObject {
    @Published public internal(set) var liveTelemetry: LiveTelemetry?       // 1 Hz — NerdHUDView only
    @Published public internal(set) var sessionCacheStatus: SessionCacheStatus
}

public struct StartupProgress: Sendable, Equatable {
    public let generation: UInt64
    public let checkpoint: StartupCheckpoint
    public var completed: Int { get }
    public var total: Int { get }
    public var fraction: Double { get }
    public var stage: StartupStage { get }
    public var isComplete: Bool { get }
}

public enum UpscaleScaler: Sendable, Hashable {
    case automatic, lineArt, lanczos
}

public struct UpscaleStatus: Sendable, Equatable {
    public let sourceSize: CGSize
    public let mlScale: Float?
    public let targetSize: CGSize
    public let disabledReason: String?
    public let degraded: Bool
    public let scaler: UpscaleScaler
}

public struct SystemCaptionRequest: Equatable, Sendable {
    public let language: String?
    public init(language: String?)
}

public struct DisplayCapabilities: Sendable, Equatable {
    public let supportsHDR: Bool
    public let supportsDolbyVision: Bool
    public let supportsHDR10: Bool
    public let supportsHLG: Bool
    public init(supportsHDR: Bool, supportsDolbyVision: Bool, supportsHDR10: Bool, supportsHLG: Bool)
}

public struct LiveTelemetry: Sendable {
    public let observedFps: Double?
    public let droppedFrameCount: Int?
    public let instantBitrateMbps: Double?
    public let averageBitrateMbps: Double?
    public let networkThroughputMbps: Double?
    public let forwardBufferSeconds: Double?
    public let readerWindowAheadBytes: Int?
    public let rssMb: Int
    public let objectAudio: ObjectAudioActivity?
    // Note: full memberwise init takes 24 parameters in fixed declaration order; prefer test helpers over constructing directly.
}

public struct ObjectAudioActivity: Equatable, Sendable {
    public let layout: SpatialSpeakerLayout
    public let objects: Int
    public let activeObjects: Int
    public let elevatedObjects: Int
    public let heightChannels: Int
}

public struct SessionCacheStatus: Sendable, Equatable {
    public static let inactive: SessionCacheStatus
    public let currentForwardBytes: Int
    // Note: full memberwise init takes 22 parameters (17 non-defaulted); use `.inactive` or test formatting helpers directly.
}

public struct SourcePrewarmReport: Sendable, Equatable {
    public let retainedBytes: Int
    public let contentLength: Int64?
    public let declined: String?
    public var isWarm: Bool { get }
}

public struct ScrubPreviewPlacement: Sendable, Equatable {
    public let actualSeconds: Double
    public let validRange: Range<Double>
}

public struct PlaybackErrorKind: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public let rawValue: String
    public static let sourceOpenFailed: PlaybackErrorKind
    public static let sourceRefused: PlaybackErrorKind
    public static let sourceCertificateRejected: PlaybackErrorKind
    public static let sourceFabricatesRanges: PlaybackErrorKind
    public static let noPlayableTrackWithinBudget: PlaybackErrorKind
    public static let vodSourceFailed: PlaybackErrorKind
    public static let sourceRateLimited: PlaybackErrorKind
    public static let audioBridgeProducedNoOutput: PlaybackErrorKind
    public static let storageExhausted: PlaybackErrorKind
}

public struct PlaybackErrorInfo: Sendable, Equatable {
    public let kind: PlaybackErrorKind
    public let underlyingDomain: String?
    public let underlyingCode: Int?
    public let hlsDiagnosticReason: HLSIngestDiagnosticReason?
    public let ffmpegErrorCode: Int?
    public let message: String
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
    public var readsContainerAttachmentsAtOpen: Bool        // default false (defers Matroska attachments after first frame)
    public var generatesBackgroundScrubPreviews: Bool
    public var serveIFramePlaylist: Bool
    public var confirmAtmos: Bool
    public var maxConcurrentSourceRequests: Int?
    public var declaredDurationSeconds: Double?
    public var untaggedVideoColor: UntaggedVideoColor         // .standard | .hdr10 | .hlg
    public var inverseTelecine: InverseTelecineMode           // .off | .auto
    public var upscalesLowResolutionVideo: Bool
    public var upscaleScaler: UpscaleScaler                   // .automatic | .lineArt | .lanczos
    public var upscalesFullHDVideo: Bool                      // default false; uses UpscaleScaler.lanczos on 1080p SDR
    public var forwardBufferSegments: Int?
    public var sessionCacheByteBudget: Int?
    public var sessionCacheFreeReserveBytes: Int
    public var progressiveSegmentDelivery: Bool
    public var externalSubtitles: [ExternalSubtitleTrack]
    public var retainsSessionCacheAfterStop: Bool
    public var liveJoinsAtPlaylistStart: Bool
    public var preferHDR10PlusOverForcedDolbyVision: Bool
    public var recognizesBitmapSubtitleText: Bool             // default false; Vision OCR -> SubtitleImage.recognizedText
    public var nativeRemoteHLSReadinessBudgetSeconds: Double? // nil keeps 45 s default
}

public struct ExternalSubtitleTrack: Sendable {
    public init(
        url: URL,
        name: String? = nil,
        language: String? = nil,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isDefault: Bool = false,
        httpHeaders: [String: String]? = nil,
        formatHint: String? = nil,
        sourceStreamIndex: Int32? = nil
    )
}

public struct AudioShaping: Equatable, Sendable, Hashable {
    public init(
        maxChannels: Int? = nil,
        dialogueGainDB: Double = 0,
        compressor: Compressor? = nil, // .night | nil
        loudnessTargetLUFS: Double? = nil,
        lfeMixDB: Double? = nil
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
    case idle, loading, playing, paused, seeking, ended, error
}

public enum PlaybackPhase: Equatable, Sendable {
    case idle, loading, playing, paused, seeking, rebuffering, stalled, ended
    case error(String)
}

public enum VideoFormat: Equatable, Sendable {
    case sdr, hdr10, hdr10Plus, dolbyVision, hlg
}

public enum DolbyVisionConversion: Equatable, Sendable {
    case profile7ToProfile81
}

public enum VideoRoute: String, Equatable, Sendable {
    case none, loopback, remoteBypass, software, audio
}

public enum AudioDelivery: String, Equatable, Sendable {
    case none, noAudioInSource, streamCopy, bridged, decoded, droppedNoPipeline, playerManaged
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
    public let channels: Int
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

public struct FontAttachment: Sendable, Equatable {
    public let filename: String
    public let mimeType: String
    public let data: Data
}

public struct SubtitleCue: Identifiable, Sendable, Equatable {
    public let id: Int
    public let startTime: Double
    public let endTime: Double
    public let body: Body // .text(String) | .image(SubtitleImage) | .richText([SubtitleTextRun])
    public let placement: SubtitleTextPlacement?
    public var recognizedText: SubtitleRecognizedText? { get }
    public var text: String? { get }
    public var isForced: Bool { get }
}

public struct SubtitleImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let position: CGRect
    public let canvasSize: CGSize
    public let isForced: Bool
    public let recognizedText: SubtitleRecognizedText?
}

public struct SubtitleRecognizedText: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public let text: String
        public let confidence: Float
        public let boundingBox: CGRect
    }
    public enum Level: Sendable, Equatable { case accurate, fast }
    public let lines: [Line]
    public let language: String?
    public let level: Level
    public var text: String? { get }
}

public struct SubtitleTextPlacement: Sendable, Equatable {
    public let alignment: Int?     // ASS numpad 1...9
    public let position: CGPoint?  // Normalized 0...1
}

public struct SubtitleColor: Sendable, Equatable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8
}

public struct SubtitleTextRun: Sendable, Equatable {
    public let text: String
    public let color: SubtitleColor?
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderlined: Bool
    public let isStruckThrough: Bool
    public let fontName: String?
    public let fontSize: Int?
    public var isStyled: Bool { get }
}

// SwiftUI & UIKit Render Surfaces
public struct AetherPlayerSurface: UIViewRepresentable {
    public init(engine: AetherEngine)
}

@MainActor
public final class AetherScrubPreviewView: UIView {
    public var videoGravity: AVLayerVideoGravity
    public func clear()
}

@MainActor
public final class AetherStillView: UIView {
    public var videoGravity: AVLayerVideoGravity
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
  - `@MainActor protocol PlayerTransportControlling`: `state`, `playbackPhase`, `videoRoute`, `currentTime`, `needsForegroundVideoRestore`, `play()`, `pause()`, `togglePlayPause()`, `seek(to:exact:)`, `setAudioDelay(_:)`, `stop(resetDisplayCriteria:finalTeardown:)`.
  - `protocol NativeAudioActivating: Sendable`: `activateNativePlaybackIfNeeded(videoRoute:) async`.
- **Linux-Testable Core Seam (`Sources/Core/Playback/`)**:
  - `PlaybackCurtainWatchdog` (`5.0 s` fallback timeout) and `PlaybackCurtainPresentationPolicy` (`180 ms` `0-RTT` silent black grace) in `PlaybackCoreAbstractions.swift`, `PlaybackStopReceipt`, `PlaybackTrackIntent`, `PlayerTimelinePolicy`, and `SeriesFlowPolicy`.
  - `RemoteScrubMath` handles paused-only clickpad pan scrubbing (`20 pt` breakaway, `0 pt` reversal deadzone, `1.35` axis lock, EMA velocity `α = 0.35`, 3-zone duration-adaptive curve, and `>= 280 ms` ring-hold progressive speeds). Note: Siri Remote capacitive circular outer-ring jog events are private to `AVPlayerViewController` (`UISwipeGestureRecognizer` / `AVPlayerBehavior` internals) and have no public UIKit/tvOS API for custom player hosts.
