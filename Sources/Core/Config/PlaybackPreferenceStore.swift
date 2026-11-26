import Foundation

/// Sideload-safe, non-isolated persistence for per-title «Norsk tale» preference
/// and per-release/`candidateId` subtitle delay (`ms`), keyed exclusively under `"luna.v1.*"`.
public struct PlaybackPreferenceStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preferNorwegianAudio(forItemId itemId: String) -> Bool {
        let key = Self.norwegianAudioKey(forItemId: itemId)
        guard !key.isEmpty else { return false }
        return defaults.bool(forKey: key)
    }

    public func setPreferNorwegianAudio(_ enabled: Bool, forItemId itemId: String) {
        let key = Self.norwegianAudioKey(forItemId: itemId)
        guard !key.isEmpty else { return }
        if enabled {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func hasStoredSubtitleDelay(forCandidateId candidateId: String) -> Bool {
        let key = Self.subtitleDelayKey(forCandidateId: candidateId)
        guard !key.isEmpty else { return false }
        return defaults.object(forKey: key) != nil
    }

    public func subtitleDelayMs(forCandidateId candidateId: String) -> Int {
        let key = Self.subtitleDelayKey(forCandidateId: candidateId)
        guard !key.isEmpty, defaults.object(forKey: key) != nil else { return 0 }
        return PlaybackSyncTimingPolicy.clampSubtitleDelayMs(defaults.integer(forKey: key))
    }

    public func setSubtitleDelayMs(_ delayMs: Int, forCandidateId candidateId: String) {
        let key = Self.subtitleDelayKey(forCandidateId: candidateId)
        guard !key.isEmpty else { return }
        let clamped = PlaybackSyncTimingPolicy.clampSubtitleDelayMs(delayMs)
        defaults.set(clamped, forKey: key)
    }

    public static func norwegianAudioKey(forItemId itemId: String) -> String {
        let clean = sanitizeKeyComponent(itemId)
        return clean.isEmpty ? "" : "\(SideloadSafeStorage.preferNorwegianAudioPrefix)\(clean)"
    }

    public static func subtitleDelayKey(forCandidateId candidateId: String) -> String {
        let clean = sanitizeKeyComponent(candidateId)
        return clean.isEmpty ? "" : "\(SideloadSafeStorage.candidateSubtitleDelayPrefix)\(clean)"
    }

    private static func sanitizeKeyComponent(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
