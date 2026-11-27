import Foundation
import Observation
import SwiftUI
import Combine
import AetherBridge

@MainActor
@Observable
final class PlayerViewModel {
    nonisolated static let audioDelayDebounceNs: UInt64 = 220_000_000
    nonisolated static let relativeSeekDebounceNs: UInt64 = 150_000_000

    let engine: AetherEngine
    let comfort: ComfortPreferences
    let transport: any PlayerTransportControlling
    let audioActivator: any NativeAudioActivating

    let sessionController: PlayerSessionController
    let trackController: PlayerTrackController
    let scrubController: PlayerScrubController
    let restoreController: PlayerRestoreController
    let qosReporter: PlayerQoSReporter

    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    @ObservationIgnored var didBindEnginePublishers: Bool = false

    init(
        engine: AetherEngine,
        comfort: ComfortPreferences,
        transport: (any PlayerTransportControlling)? = nil,
        audioActivator: any NativeAudioActivating = DefaultNativeAudioActivator(),
        preferenceStore: PlaybackPreferenceStore = PlaybackPreferenceStore(),
        bindOnInit: Bool = true
    ) {
        let resolvedTransport = transport ?? AetherEngineTransport(engine: engine)
        self.engine = engine
        self.comfort = comfort
        self.transport = resolvedTransport
        self.audioActivator = audioActivator

        self.sessionController = PlayerSessionController(
            engine: engine, comfort: comfort, transport: resolvedTransport, audioActivator: audioActivator
        )
        self.trackController = PlayerTrackController(
            engine: engine, comfort: comfort, transport: resolvedTransport, preferenceStore: preferenceStore
        )
        self.scrubController = PlayerScrubController(
            engine: engine, transport: resolvedTransport, audioActivator: audioActivator
        )
        self.restoreController = PlayerRestoreController(
            comfort: comfort, transport: resolvedTransport, audioActivator: audioActivator
        )
        self.qosReporter = PlayerQoSReporter(
            comfort: comfort, transport: resolvedTransport
        )

        self.sessionController.bindHost(self)
        self.trackController.bindHost(self)
        self.scrubController.bindHost(self)
        self.restoreController.bindHost(self)
        self.qosReporter.bindHost(self)

        if bindOnInit { bindEnginePublishersIfNeeded() }
    }

    func bindEnginePublishersIfNeeded() {
        guard !didBindEnginePublishers else { return }
        didBindEnginePublishers = true
        bindEnginePublishers()
    }

    // MARK: - Session Controller Forwarders

    var isResolving: Bool { get { sessionController.isResolving } set { sessionController.isResolving = newValue } }
    var startupState: PlayerStartupState { sessionController.startupState }
    var fatalError: String? { get { sessionController.fatalError } set { sessionController.fatalError = newValue } }
    var currentRequest: PlaybackLaunchRequest? { get { sessionController.currentRequest } set { sessionController.currentRequest = newValue } }
    var activeSession: TvPlaybackSession? { get { sessionController.activeSession } set { sessionController.activeSession = newValue } }
    var alternatives: [TvCandidateInfo] { get { sessionController.alternatives } set { sessionController.alternatives = newValue } }
    var alternativesSessionId: String? { sessionController.alternativesSessionId }
    var isLoadingAlternatives: Bool { get { sessionController.isLoadingAlternatives } set { sessionController.isLoadingAlternatives = newValue } }
    var isSwitchingSource: Bool { get { sessionController.isSwitchingSource } set { sessionController.isSwitchingSource = newValue } }
    var hasFirstFrameReadyForDisplay: Bool { get { sessionController.hasFirstFrameReadyForDisplay } set { sessionController.hasFirstFrameReadyForDisplay = newValue } }
    var isAwaitingDisplaySwitch: Bool { get { sessionController.isAwaitingDisplaySwitch } set { sessionController.isAwaitingDisplaySwitch = newValue } }
    var firstFrameFallbackUnlocked: Bool { get { sessionController.firstFrameFallbackUnlocked } set { sessionController.firstFrameFallbackUnlocked = newValue } }
    var resolveStageLabel: String { get { startupState.resolveStageLabel } set { if startupState.resolveStageLabel != newValue { startupState.resolveStageLabel = newValue } } }
    var resolvePercent: Int { get { startupState.resolvePercent } set { if startupState.resolvePercent != newValue { startupState.resolvePercent = newValue } } }
    var resolveHeadline: String? { get { startupState.resolveHeadline } set { if startupState.resolveHeadline != newValue { startupState.resolveHeadline = newValue } } }
    var activeClient: LunaCoreClient? { get { sessionController.activeClient } set { sessionController.activeClient = newValue } }
    var engineOwnerToken: UInt64 { sessionController.engineOwnerToken }
    var isDismissing: Bool { sessionController.isDismissing }
    var isTeardownCompleted: Bool { sessionController.isTeardownCompleted }
    var isPictureReadyForReveal: Bool { sessionController.isPictureReadyForReveal }
    var effectiveDurationSeconds: Double { sessionController.effectiveDurationSeconds }
    var onUnauthorized: (() -> Void)? { get { sessionController.onUnauthorized } set { sessionController.onUnauthorized = newValue } }

    func configurePreviewPlayback(
        request: PlaybackLaunchRequest, session: TvPlaybackSession, client: LunaCoreClient?,
        audioOptions: [PlayerDrawerAudioOption] = PreviewMockFixtures.previewAudioOptions,
        subtitleOptions: [PlayerDrawerSubtitleOption] = PreviewMockFixtures.previewSubtitleOptions,
        candidates: [TvCandidateInfo] = PreviewMockFixtures.previewCandidates
    ) {
        sessionController.configurePreviewPlayback(
            request: request, session: session, client: client,
            audioOptions: audioOptions, subtitleOptions: subtitleOptions, candidates: candidates
        )
    }
    func start(request: PlaybackLaunchRequest, client: LunaCoreClient?) { sessionController.start(request: request, client: client) }
    func playNextEpisode(_ next: TvNextEpisodeSummary) { sessionController.playNextEpisode(next) }
    func loadAlternatives() async { await sessionController.loadAlternatives() }
    func triggerSourceSwitch(to candidateId: String) { sessionController.triggerSourceSwitch(to: candidateId) }
    func switchSource(to candidateId: String) async { await sessionController.switchSource(to: candidateId) }
    func prepareForDismissal() { sessionController.prepareForDismissal() }
    func teardownAndStop(
        onComplete: (@MainActor @Sendable () -> Void)? = nil,
        onStopReceipt: (@MainActor @Sendable (PlaybackStopReceipt) -> Void)? = nil
    ) {
        sessionController.teardownAndStop(onComplete: onComplete, onStopReceipt: onStopReceipt)
    }

    // MARK: - Track Controller Forwarders

    var durationSeconds: Double { get { trackController.durationSeconds } set { trackController.durationSeconds = newValue } }
    var activeAudioTrackIndex: Int? { get { trackController.activeAudioTrackIndex } set { trackController.activeAudioTrackIndex = newValue } }
    var audioDelayMs: Int { get { trackController.audioDelayMs } set { trackController.audioDelayMs = newValue } }
    var audioEnhancement: AudioEnhancementMode { get { trackController.audioEnhancement } set { trackController.audioEnhancement = newValue } }
    var subtitleTracks: [TrackInfo] { get { trackController.subtitleTracks } set { trackController.subtitleTracks = newValue } }
    var activeSubtitleTrackIndex: Int? { get { trackController.activeSubtitleTrackIndex } set { trackController.activeSubtitleTrackIndex = newValue } }
    var subtitleDelayMs: Int { get { trackController.subtitleDelayMs } set { trackController.subtitleDelayMs = newValue } }
    var subtitleDelaySeconds: Double { trackController.subtitleDelaySeconds }
    var previewSubtitleOptions: [PlayerDrawerSubtitleOption] { get { trackController.previewSubtitleOptions } set { trackController.previewSubtitleOptions = newValue } }
    var chapters: [PlaybackChapter] { get { trackController.chapters } set { trackController.chapters = newValue } }
    var isWirelessAudioRouteActive: Bool { get { trackController.isWirelessAudioRouteActive } set { trackController.isWirelessAudioRouteActive = newValue } }
    var isBinauralAudioRouteActive: Bool { get { trackController.isBinauralAudioRouteActive } set { trackController.isBinauralAudioRouteActive = newValue } }
    var kveldslysLockReason: String? { trackController.kveldslysLockReason }
    var preferNorwegianAudio: Bool { trackController.preferNorwegianAudio }
    var hasNorwegianAudioTrack: Bool { trackController.hasNorwegianAudioTrack }
    var isSearchingSubtitles: Bool { trackController.isSearchingSubtitles }
    var isAutoAligningSubtitles: Bool { trackController.isAutoAligningSubtitles }
    var subtitleActionStatusMessage: String? { trackController.subtitleActionStatusMessage }

    func selectAudioTrack(_ index: Int) { trackController.selectAudioTrack(index) }
    func togglePreferNorwegianAudio() { trackController.togglePreferNorwegianAudio() }
    func adjustAudioDelay(byMs deltaMs: Int) { trackController.adjustAudioDelay(byMs: deltaMs) }
    func flushPendingAudioDelayCommitIfNeeded() { trackController.flushPendingAudioDelayCommitIfNeeded() }
    func handleAudioRouteChange(isWirelessOverride: Bool? = nil, isBinauralOverride: Bool? = nil) {
        trackController.handleAudioRouteChange(isWirelessOverride: isWirelessOverride, isBinauralOverride: isBinauralOverride)
    }
    func setAudioEnhancement(_ mode: AudioEnhancementMode) { trackController.setAudioEnhancement(mode) }
    func selectSubtitleManually(_ index: Int) { trackController.selectSubtitleManually(index) }
    func clearSubtitleManually() { trackController.clearSubtitleManually() }
    func adjustSubtitleDelay(byMs deltaMs: Int) { trackController.adjustSubtitleDelay(byMs: deltaMs) }
    func searchAndAttachSubtitles() { trackController.searchAndAttachSubtitles() }
    func autoAlignActiveSubtitle() { trackController.autoAlignActiveSubtitle() }
    func switchToHDR10BaseLayer() { trackController.switchToHDR10BaseLayer() }

    // MARK: - Scrub Controller Forwarders

    var previewPlayheadOverrideSeconds: Double? { get { scrubController.previewPlayheadOverrideSeconds } set { scrubController.previewPlayheadOverrideSeconds = newValue } }
    var coalescedSeekDelta: Double { get { scrubController.coalescedSeekDelta } set { scrubController.coalescedSeekDelta = newValue } }
    var coalescedSeekPreviewTarget: Double? { get { scrubController.coalescedSeekPreviewTarget } set { scrubController.coalescedSeekPreviewTarget = newValue } }
    var isScrubbing: Bool { get { scrubController.isScrubbing } set { scrubController.isScrubbing = newValue } }
    var scrubState: PlayerScrubState { scrubController.scrubState }
    var scrubCommitTask: Task<Void, Never>? { scrubController.scrubCommitTask }
    var coalescedSeekTask: Task<Void, Never>? { scrubController.coalescedSeekTask }
    var chapterSeekTask: Task<Void, Never>? { scrubController.chapterSeekTask }

    func beginTouchScrub() { scrubController.beginTouchScrub() }
    func configurePreviewScrub(originSeconds: Double = 1122, targetSeconds: Double = 2145, previewImage: CGImage?) {
        scrubController.configurePreviewScrub(originSeconds: originSeconds, targetSeconds: targetSeconds, previewImage: previewImage)
    }
    func updateTouchScrub(deltaSeconds: Double) { scrubController.updateTouchScrub(deltaSeconds: deltaSeconds) }
    func stepTouchScrub(by deltaSeconds: Double) { scrubController.stepTouchScrub(by: deltaSeconds) }
    func beginRingHoldScrub(direction: Int) { scrubController.beginRingHoldScrub(direction: direction) }
    func endRingHoldScrub(cancelled: Bool = false) { scrubController.endRingHoldScrub(cancelled: cancelled) }
    func commitTouchScrub() { scrubController.commitTouchScrub() }
    func commitTouchScrubPaused() { scrubController.commitTouchScrubPaused() }
    func cancelTouchScrub() { scrubController.cancelTouchScrub() }
    func coalesceRelativeSeek(delta: Double) { scrubController.coalesceRelativeSeek(delta: delta) }
    func seekToChapter(_ chapter: PlaybackChapter) { scrubController.seekToChapter(chapter) }
    func seekToPosition(_ rawTargetSeconds: Double, exact: Bool = true) { scrubController.seekToPosition(rawTargetSeconds, exact: exact) }

    // MARK: - Restore & QoS Forwarders

    var isRestoringFromBackground: Bool { get { restoreController.isRestoringFromBackground } set { restoreController.isRestoringFromBackground = newValue } }
    var lastForegroundPlaybackWasPlaying: Bool { get { restoreController.lastForegroundPlaybackWasPlaying } set { restoreController.lastForegroundPlaybackWasPlaying = newValue } }
    var userDesiredPlayingDuringRestore: Bool? { get { restoreController.userDesiredPlayingDuringRestore } set { restoreController.userDesiredPlayingDuringRestore = newValue } }
    var needsNativeAudioActivationAfterPausedRestore: Bool { get { restoreController.needsNativeAudioActivationAfterPausedRestore } set { restoreController.needsNativeAudioActivationAfterPausedRestore = newValue } }
    var pausedRestoreResumeTask: Task<Void, Never>? { restoreController.pausedRestoreResumeTask }
    var playbackPhase: PlaybackPhase { get { qosReporter.playbackPhase } set { qosReporter.playbackPhase = newValue } }
    var videoFormat: VideoFormat { get { qosReporter.videoFormat } set { qosReporter.videoFormat = newValue } }
    var isMetalFXActive: Bool { qosReporter.isMetalFXActive }
    var activeMetalFXBadge: String? { qosReporter.activeMetalFXBadge }
    var remoteCommandToastMessage: String? { qosReporter.remoteCommandToastMessage }
    var suggestsHDR10BaseLayer: Bool { qosReporter.suggestsHDR10BaseLayer }
    var canSwitchToHDR10BaseLayer: Bool { qosReporter.canSwitchToHDR10BaseLayer }

    func updateInitialScenePhase(_ phase: ScenePhase) { restoreController.updateInitialScenePhase(phase) }
    func handleScenePhaseChange(_ phase: ScenePhase) { restoreController.handleScenePhaseChange(phase) }
    func togglePlayPause() { restoreController.togglePlayPause() }
    func handleHeartbeatPendingCommand(_ cmd: TvPendingCommand, client: LunaCoreClient?, currentPosition: Double) async {
        await qosReporter.handleHeartbeatPendingCommand(cmd, client: client, currentPosition: currentPosition)
    }

    func cancelAllSessionTasks() {
        restoreController.cancelTasks()
        scrubController.cancelTasks()
        trackController.cancelTasks()
        sessionController.cancelSessionTasks()
        qosReporter.cancelTasks()
    }

    // MARK: - Static Restore Helpers

    nonisolated static func isActiveTransportIntent(playbackPhase: PlaybackPhase, engineState: PlaybackState) -> Bool {
        PlayerRestoreController.isActiveTransportIntent(playbackPhase: playbackPhase, engineState: engineState)
    }
    nonisolated static func resolvedPostRestorePlayingIntent(defaultShouldPlay: Bool, userOverride: Bool?) -> Bool {
        PlayerRestoreController.resolvedPostRestorePlayingIntent(defaultShouldPlay: defaultShouldPlay, userOverride: userOverride)
    }
    nonisolated static func shouldActivateNativeAudioDuringRestore(shouldPlay: Bool, videoRoute: VideoRoute) -> Bool {
        PlayerRestoreController.shouldActivateNativeAudioDuringRestore(shouldPlay: shouldPlay, videoRoute: videoRoute)
    }
    nonisolated static func shouldAttemptForegroundVideoRestore(
        needsForegroundVideoRestore: Bool, hasActiveSession: Bool, isResolving: Bool,
        isSwitchingSource: Bool, isRestoringFromBackground: Bool, hasFatalError: Bool, didTeardown: Bool
    ) -> Bool {
        PlayerRestoreController.shouldAttemptForegroundVideoRestore(
            needsForegroundVideoRestore: needsForegroundVideoRestore, hasActiveSession: hasActiveSession,
            isResolving: isResolving, isSwitchingSource: isSwitchingSource,
            isRestoringFromBackground: isRestoringFromBackground, hasFatalError: hasFatalError, didTeardown: didTeardown
        )
    }
    nonisolated static func shouldActivateNativeAudioBeforePlayOnResume(wasPlaying: Bool, needsNativeAudioActivationAfterPausedRestore: Bool) -> Bool {
        PlayerRestoreController.shouldActivateNativeAudioBeforePlayOnResume(
            wasPlaying: wasPlaying, needsNativeAudioActivationAfterPausedRestore: needsNativeAudioActivationAfterPausedRestore
        )
    }
}
