import Foundation

/// Pure-Swift transport state mirroring `AetherEngine.PlaybackState` without SDK dependencies.
public enum CorePlaybackState: String, Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case ended
    case failed
}

/// Pure-Swift lifecycle phase mirroring `AetherEngine.PlaybackPhase` without SDK dependencies.
public enum CorePlaybackPhase: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case rebuffering
    case stalled
    case ended
    case error(String)
}

/// Byte-range / prewarm reader abstraction (`IOReader`) decoupling HTTP 206 & VFS prewarm probes
/// from platform transport implementations so buffer/spindown rules can be verified on Linux.
public protocol IOReader: Sendable {
    func isPrewarmed(url: URL) async -> Bool
    @discardableResult
    func prewarm(url: URL, httpHeaders: [String: String], byteBudget: Int) async throws -> Int
    func readRange(url: URL, httpHeaders: [String: String], offset: Int64, length: Int) async throws -> Data
    func discardPrewarmedSources() async
}

/// Pure-Swift `PlaybackEngine` protocol decoupling playback state machines, curtain gates,
/// and watchdog timers from `AetherEngine` / `AVFoundation` so core playback flows compile on Linux.
public protocol PlaybackEngine: AnyObject, Sendable {
    var state: CorePlaybackState { get async }
    var phase: CorePlaybackPhase { get async }
    var currentTime: Double { get async }
    var duration: Double { get async }
    var bufferedPosition: Double { get async }
    var hasFirstFrameReadyForDisplay: Bool { get async }
    var isAwaitingDisplaySwitch: Bool { get async }
    var needsForegroundVideoRestore: Bool { get async }

    func load(
        url: URL,
        httpHeaders: [String: String],
        startPosition: Double?,
        autoplay: Bool
    ) async throws
    func prepareForItemReplacement() async
    func play() async
    func pause() async
    func togglePlayPause() async
    func seek(to seconds: Double, exact: Bool) async
    func stop(resetDisplayCriteria: Bool) async
}

/// Deterministic HDMI display-switch curtain gate & stall watchdog evaluator.
///
/// Enforces Luna's cinema curtain invariant:
/// - Keep `ResolvingCurtainView` opaque until `hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch`
/// - Force-unlock after `fallbackTimeoutSeconds` (5.0 s default) so a missed HDMI EDID notification never hangs black
/// - Detect prolonged playback stalls without triggering false positives while paused or scrubbing
public struct PlaybackCurtainWatchdog: Equatable, Sendable {
    public static let defaultFallbackTimeoutSeconds: Double = 5.0
    public static let defaultStallTimeoutSeconds: Double = 8.0

    public let fallbackTimeoutSeconds: Double
    public let stallTimeoutSeconds: Double

    public private(set) var loadCompletedAtSeconds: Double?
    public private(set) var firstFrameFallbackUnlocked: Bool = false
    public private(set) var stallStartedAtSeconds: Double?
    public private(set) var stallRecoveryCount: Int = 0

    public init(
        fallbackTimeoutSeconds: Double = Self.defaultFallbackTimeoutSeconds,
        stallTimeoutSeconds: Double = Self.defaultStallTimeoutSeconds
    ) {
        self.fallbackTimeoutSeconds = max(0.5, fallbackTimeoutSeconds)
        self.stallTimeoutSeconds = max(1.0, stallTimeoutSeconds)
    }

    public static func isPictureReadyForReveal(
        hasFatalError: Bool,
        isSwitchingSource: Bool,
        isResolving: Bool,
        isRestoringFromBackground: Bool,
        needsForegroundVideoRestore: Bool,
        firstFrameFallbackUnlocked: Bool,
        hasFirstFrameReadyForDisplay: Bool,
        isAwaitingDisplaySwitch: Bool
    ) -> Bool {
        if hasFatalError {
            return false
        }
        if isSwitchingSource {
            return true
        }
        if isResolving || isRestoringFromBackground || needsForegroundVideoRestore {
            return false
        }
        if firstFrameFallbackUnlocked {
            return true
        }
        return hasFirstFrameReadyForDisplay && !isAwaitingDisplaySwitch
    }

    public mutating func resetForNewLoad() {
        loadCompletedAtSeconds = nil
        firstFrameFallbackUnlocked = false
        stallStartedAtSeconds = nil
    }

    public mutating func markEngineLoadCompleted(nowSeconds: Double) {
        loadCompletedAtSeconds = nowSeconds
        firstFrameFallbackUnlocked = false
    }

    /// Evaluates whether the 5-second HDMI display-switch fallback watchdog should unlock the curtain.
    @discardableResult
    public mutating func evaluateCurtainWatchdog(
        nowSeconds: Double,
        hasFatalError: Bool,
        isSwitchingSource: Bool,
        isResolving: Bool,
        isRestoringFromBackground: Bool,
        needsForegroundVideoRestore: Bool,
        hasFirstFrameReadyForDisplay: Bool,
        isAwaitingDisplaySwitch: Bool
    ) -> Bool {
        if let loadedAt = loadCompletedAtSeconds,
           !firstFrameFallbackUnlocked,
           !isResolving,
           !hasFatalError,
           (nowSeconds - loadedAt) >= fallbackTimeoutSeconds {
            firstFrameFallbackUnlocked = true
        }

        return Self.isPictureReadyForReveal(
            hasFatalError: hasFatalError,
            isSwitchingSource: isSwitchingSource,
            isResolving: isResolving,
            isRestoringFromBackground: isRestoringFromBackground,
            needsForegroundVideoRestore: needsForegroundVideoRestore,
            firstFrameFallbackUnlocked: firstFrameFallbackUnlocked,
            hasFirstFrameReadyForDisplay: hasFirstFrameReadyForDisplay,
            isAwaitingDisplaySwitch: isAwaitingDisplaySwitch
        )
    }

    /// Evaluates whether an active `.stalled` / `.rebuffering` phase has exceeded `stallTimeoutSeconds`.
    public mutating func evaluateStallWatchdog(
        nowSeconds: Double,
        phase: CorePlaybackPhase,
        isScrubbing: Bool
    ) -> Bool {
        guard !isScrubbing else {
            stallStartedAtSeconds = nil
            return false
        }
        switch phase {
        case .stalled, .rebuffering:
            if let started = stallStartedAtSeconds {
                if (nowSeconds - started) >= stallTimeoutSeconds {
                    stallRecoveryCount += 1
                    stallStartedAtSeconds = nowSeconds
                    return true
                }
                return false
            } else {
                stallStartedAtSeconds = nowSeconds
                return false
            }
        default:
            stallStartedAtSeconds = nil
            return false
        }
    }
}

/// Actor-isolated playback coordinator state machine orchestrating `PlaybackEngine`, `IOReader`
/// prewarm rules (never prewarming archive HDDs when `canClientPrewarmBytes == false`),
/// seamless source replacement, and `PlaybackCurtainWatchdog`.
public actor PlaybackCoordinatorStateMachine {
    public static let defaultPrewarmBudgetBytes = 8 * 1024 * 1024

    private let engine: any PlaybackEngine
    private let ioReader: (any IOReader)?
    public private(set) var watchdog: PlaybackCurtainWatchdog
    public private(set) var activeSession: TvPlaybackSession?
    public private(set) var isResolving: Bool = false
    public private(set) var isSwitchingSource: Bool = false
    public private(set) var fatalError: String?

    public init(
        engine: any PlaybackEngine,
        ioReader: (any IOReader)? = nil,
        watchdog: PlaybackCurtainWatchdog = PlaybackCurtainWatchdog()
    ) {
        self.engine = engine
        self.ioReader = ioReader
        self.watchdog = watchdog
    }

    /// Prewarms initial stream bytes ONLY when `canClientPrewarmBytes == true` so mechanical
    /// archive HDDs are never woken by detail-page hover or background pre-resolve.
    @discardableResult
    public func prewarmIfAllowed(
        session: TvPlaybackSession,
        canClientPrewarmBytes: Bool,
        baseURL: URL,
        headers: [String: String]
    ) async throws -> Bool {
        guard canClientPrewarmBytes,
              let reader = ioReader,
              let streamURL = resolveStreamURL(session.stream.url, baseURL: baseURL) else {
            return false
        }
        if await reader.isPrewarmed(url: streamURL) {
            return false
        }
        _ = try await reader.prewarm(
            url: streamURL,
            httpHeaders: headers,
            byteBudget: Self.defaultPrewarmBudgetBytes
        )
        return true
    }

    public func startSession(
        _ session: TvPlaybackSession,
        baseURL: URL,
        headers: [String: String],
        overrideStartPosition: Double? = nil,
        autoplay: Bool = true,
        nowSeconds: Double = 0
    ) async throws {
        guard let streamURL = resolveStreamURL(session.stream.url, baseURL: baseURL) else {
            let err = LunaCoreError.invalidURL(session.stream.url)
            fatalError = err.localizedDescription
            throw err
        }

        fatalError = nil
        isResolving = true
        watchdog.resetForNewLoad()

        do {
            let resumePos = overrideStartPosition ?? session.stream.startPositionSeconds ?? 0
            try await engine.load(
                url: streamURL,
                httpHeaders: headers,
                startPosition: resumePos > 0.5 ? resumePos : nil,
                autoplay: autoplay
            )
            activeSession = session
            isResolving = false
            watchdog.markEngineLoadCompleted(nowSeconds: nowSeconds)
        } catch {
            isResolving = false
            fatalError = error.localizedDescription
            throw error
        }
    }

    public func switchSource(
        to updatedSession: TvPlaybackSession,
        baseURL: URL,
        headers: [String: String],
        nowSeconds: Double = 0
    ) async throws {
        guard let streamURL = resolveStreamURL(updatedSession.stream.url, baseURL: baseURL) else {
            throw LunaCoreError.invalidURL(updatedSession.stream.url)
        }
        let preservedPos = await engine.currentTime
        isSwitchingSource = true
        await engine.prepareForItemReplacement()
        do {
            let targetPos = updatedSession.stream.startPositionSeconds ?? preservedPos
            try await engine.load(
                url: streamURL,
                httpHeaders: headers,
                startPosition: targetPos > 0.5 ? targetPos : nil,
                autoplay: true
            )
            activeSession = updatedSession
            isSwitchingSource = false
            watchdog.markEngineLoadCompleted(nowSeconds: nowSeconds)
        } catch {
            isSwitchingSource = false
            throw error
        }
    }

    public func isPictureReadyForReveal(nowSeconds: Double) async -> Bool {
        let hasFirstFrame = await engine.hasFirstFrameReadyForDisplay
        let awaitingSwitch = await engine.isAwaitingDisplaySwitch
        let needsRestore = await engine.needsForegroundVideoRestore
        return watchdog.evaluateCurtainWatchdog(
            nowSeconds: nowSeconds,
            hasFatalError: fatalError != nil,
            isSwitchingSource: isSwitchingSource,
            isResolving: isResolving,
            isRestoringFromBackground: false,
            needsForegroundVideoRestore: needsRestore,
            hasFirstFrameReadyForDisplay: hasFirstFrame,
            isAwaitingDisplaySwitch: awaitingSwitch
        )
    }

    public func pollStallRecoveryIfNeeded(nowSeconds: Double, isScrubbing: Bool = false) async -> Bool {
        let currentPhase = await engine.phase
        let shouldRecover = watchdog.evaluateStallWatchdog(
            nowSeconds: nowSeconds,
            phase: currentPhase,
            isScrubbing: isScrubbing
        )
        if shouldRecover {
            let pos = await engine.currentTime
            await engine.seek(to: pos, exact: false)
            await engine.play()
        }
        return shouldRecover
    }

    public func teardown(resetDisplayCriteria: Bool = true) async {
        isResolving = false
        isSwitchingSource = false
        activeSession = nil
        watchdog.resetForNewLoad()
        await engine.stop(resetDisplayCriteria: resetDisplayCriteria)
    }

    private func resolveStreamURL(_ rawPath: String, baseURL: URL) -> URL? {
        if rawPath.hasPrefix("http://") || rawPath.hasPrefix("https://") {
            return URL(string: rawPath)
        }
        let cleanBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanRel = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        return URL(string: "\(cleanBase)\(cleanRel)")
    }
}
