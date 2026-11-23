import Foundation

/// Identifies which bottom-right series continuity overlay is currently visible on screen
/// so `SubtitleOverlayLayout` and 1-click Siri Remote focus transitions stay deterministic.
public enum ActiveSeriesOverlayKind: String, CaseIterable, Equatable, Sendable {
    case none
    case skipPrompt
    case nextEpisodeCard

    public static func resolve(
        showNextEpisodeCard: Bool,
        hasActiveIntro: Bool,
        isResting: Bool
    ) -> ActiveSeriesOverlayKind {
        guard !isResting else { return .none }
        if showNextEpisodeCard {
            return .nextEpisodeCard
        }
        if hasActiveIntro {
            return .skipPrompt
        }
        return .none
    }
}

public enum SeriesPromptControl: String, Hashable, Equatable, Sendable {
    case restartFromBeginning
    case skipIntro
    case playNext
    case dismissNext
}

public enum SeriesPromptMoveDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

public enum SeriesPromptMoveOutcome: Equatable, Sendable {
    case focusControl(SeriesPromptControl)
    case silentReturnToCanvas(dismissResumeBanner: Bool)
    case focusQuickActions(dismissResumeBanner: Bool)
    case seekRelativeAndReturnToCanvas(seconds: Double, dismissResumeBanner: Bool)
    case noOp
}

/// Pure, platform-independent navigation, 1-click auto-focus, and `10 s` countdown rules
/// for `SeriesFlowOverlays` (tested natively on both Linux `LunaCore` and tvOS).
public enum SeriesFlowPolicy: Sendable {
    public static let nextEpisodeCountdownStartSeconds: Int = 10

    /// Deterministic Siri Remote directional matrix for all controls in `SeriesFlowOverlays`.
    public static func resolveMove(
        from control: SeriesPromptControl,
        direction: SeriesPromptMoveDirection,
        hasActiveResumeBanner: Bool = false
    ) -> SeriesPromptMoveOutcome {
        switch control {
        case .playNext:
            switch direction {
            case .right:
                return .focusControl(.dismissNext)
            case .left:
                return .seekRelativeAndReturnToCanvas(seconds: -10, dismissResumeBanner: false)
            case .up:
                return .silentReturnToCanvas(dismissResumeBanner: false)
            case .down:
                return .focusQuickActions(dismissResumeBanner: false)
            }

        case .dismissNext:
            switch direction {
            case .left:
                return .focusControl(.playNext)
            case .right:
                return .noOp
            case .up:
                return .silentReturnToCanvas(dismissResumeBanner: false)
            case .down:
                return .focusQuickActions(dismissResumeBanner: false)
            }

        case .skipIntro:
            switch direction {
            case .left:
                return .seekRelativeAndReturnToCanvas(seconds: -10, dismissResumeBanner: hasActiveResumeBanner)
            case .right:
                return .seekRelativeAndReturnToCanvas(seconds: 10, dismissResumeBanner: hasActiveResumeBanner)
            case .up:
                return .silentReturnToCanvas(dismissResumeBanner: false)
            case .down:
                return .focusQuickActions(dismissResumeBanner: hasActiveResumeBanner)
            }

        case .restartFromBeginning:
            switch direction {
            case .up:
                return .noOp
            case .down:
                return .silentReturnToCanvas(dismissResumeBanner: false)
            case .left:
                return .seekRelativeAndReturnToCanvas(seconds: -10, dismissResumeBanner: true)
            case .right:
                return .seekRelativeAndReturnToCanvas(seconds: 10, dismissResumeBanner: true)
            }
        }
    }

    /// Evaluates whether a newly revealed bottom-right series card should automatically claim
    /// Siri Remote focus for 1-click Center activation.
    ///
    /// Note: The top `Start på nytt` resume banner is intentionally excluded so clicking Center
    /// immediately after resuming pauses video rather than rewinding to `00:00`.
    public static func autoFocusTargetOnOverlayTransition(
        previousKind: ActiveSeriesOverlayKind,
        newKind: ActiveSeriesOverlayKind,
        isPlaying: Bool,
        isBottomBarVisible: Bool,
        isResting: Bool,
        isQuickPanelOpen: Bool,
        isQuickActionsModeActive: Bool,
        isScrubbing: Bool
    ) -> SeriesPromptControl? {
        guard newKind != .none,
              newKind != previousKind,
              isPlaying,
              !isBottomBarVisible,
              !isResting,
              !isQuickPanelOpen,
              !isQuickActionsModeActive,
              !isScrubbing else {
            return nil
        }
        switch newKind {
        case .skipPrompt:
            return .skipIntro
        case .nextEpisodeCard:
            return .playNext
        case .none:
            return nil
        }
    }

    public static func shouldFreezeCountdown(
        isPlaying: Bool,
        isQuickPanelOpen: Bool,
        isScrubbing: Bool,
        isQuickActionsModeActive: Bool
    ) -> Bool {
        !isPlaying || isQuickPanelOpen || isScrubbing || isQuickActionsModeActive
    }

    public static func primaryNextButtonTitle(
        autoPlayEnabled: Bool,
        remainingSeconds: Int?
    ) -> String {
        if autoPlayEnabled, let secs = remainingSeconds, secs > 0 {
            return "Spill nå · \(secs) s"
        }
        return "Spill nå"
    }

    /// Ensures EOF (`playbackPhase == .ended`) respects an explicit `Skjul` or `Menu` dismissal
    /// of the `Neste episode` card for the active session, closing cleanly instead of forcing a jump.
    public static func shouldAutoPlayNextEpisodeOnEnded(
        autoPlayEnabled: Bool,
        hasNextEpisode: Bool,
        activeSessionID: String?,
        dismissedNextForSessionID: String?
    ) -> Bool {
        guard autoPlayEnabled, hasNextEpisode else { return false }
        if let sid = activeSessionID, !sid.isEmpty, dismissedNextForSessionID == sid {
            return false
        }
        return true
    }
}

/// Isolated `10 → 0 s` countdown state machine for `Neste episode`.
public struct NextEpisodeCountdownState: Equatable, Sendable {
    public private(set) var remainingSeconds: Int?
    public private(set) var didTriggerAutoAdvance: Bool = false
    public private(set) var isCancelledForSession: Bool = false

    public init(
        remainingSeconds: Int? = nil,
        didTriggerAutoAdvance: Bool = false,
        isCancelledForSession: Bool = false
    ) {
        self.remainingSeconds = remainingSeconds
        self.didTriggerAutoAdvance = didTriggerAutoAdvance
        self.isCancelledForSession = isCancelledForSession
    }

    public mutating func beginIfNeeded(
        autoPlayEnabled: Bool,
        startSeconds: Int = SeriesFlowPolicy.nextEpisodeCountdownStartSeconds
    ) {
        guard autoPlayEnabled, !isCancelledForSession, !didTriggerAutoAdvance else {
            if !autoPlayEnabled {
                remainingSeconds = nil
            }
            return
        }
        if remainingSeconds == nil {
            remainingSeconds = max(1, startSeconds)
        }
    }

    public mutating func hideWithoutCancellingSession() {
        remainingSeconds = nil
    }

    public mutating func cancelForSession() {
        remainingSeconds = nil
        isCancelledForSession = true
    }

    public mutating func resetForNewSession() {
        remainingSeconds = nil
        didTriggerAutoAdvance = false
        isCancelledForSession = false
    }

    /// Advances the countdown by 1 second unless frozen or cancelled.
    /// Returns `true` **at most once** when the countdown reaches `0` and should trigger `playNextEpisode`.
    public mutating func tickOneSecond(
        autoPlayEnabled: Bool,
        isPlaying: Bool,
        isQuickPanelOpen: Bool,
        isScrubbing: Bool,
        isQuickActionsModeActive: Bool,
        isSwitchingSource: Bool
    ) -> Bool {
        guard autoPlayEnabled, !isCancelledForSession, !didTriggerAutoAdvance else {
            if !autoPlayEnabled {
                remainingSeconds = nil
            }
            return false
        }
        guard !SeriesFlowPolicy.shouldFreezeCountdown(
            isPlaying: isPlaying,
            isQuickPanelOpen: isQuickPanelOpen,
            isScrubbing: isScrubbing,
            isQuickActionsModeActive: isQuickActionsModeActive
        ), !isSwitchingSource else {
            return false
        }
        guard let current = remainingSeconds else {
            return false
        }
        let next = current - 1
        if next <= 0 {
            remainingSeconds = 0
            didTriggerAutoAdvance = true
            return true
        }
        remainingSeconds = next
        return false
    }
}
