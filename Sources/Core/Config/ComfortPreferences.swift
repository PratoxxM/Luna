import Observation
import SwiftUI
import AetherBridge

public extension HDRSubtitlePreset {
    /// Applies warm Lampelys subtitle dimming identically across SDR, HDR10, HDR10+, and Dolby Vision
    /// without raw `#FFFFFF` glare.
    func foregroundColor(isHDR _: Bool = true) -> Color {
        let c = rgbComponents
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// GPU `.colorMultiply` tint for PGS/DVB bitmap cues:
    /// multiplying black outline pixels `(0, 0, 0, α)` yields `(0, 0, 0, α)` (100 % jet black),
    /// while bright white glyph fills `(1, 1, 1, α)` dim smoothly to warm white across SDR and HDR.
    func bitmapMultiplyColor(isHDR: Bool = true) -> Color {
        foregroundColor(isHDR: isHDR)
    }
}

public extension SubtitleFontSizePreset {
    var pointSize: CGFloat {
        CGFloat(pointSizeValue)
    }
}

@MainActor
@Observable
public final class ComfortPreferences {
    public static let audioDelayRangeMs: ClosedRange<Int> = PlaybackSyncTimingPolicy.audioDelayRangeMs

    public static func clampAudioDelayMs(_ rawMs: Int) -> Int {
        PlaybackSyncTimingPolicy.clampAudioDelayMs(rawMs)
    }

    public static func formatAudioDelayMs(_ ms: Int) -> String {
        ms == 0 ? "0 ms" : String(format: "%+d ms", ms)
    }

    public static func displayAudioDelayMs(_ ms: Int) -> String {
        PlaybackSyncTimingPolicy.formatSignedDelayMs(ms)
    }

    public var hdrSubtitlePreset: HDRSubtitlePreset {
        didSet {
            guard oldValue != hdrSubtitlePreset else { return }
            defaults.set(hdrSubtitlePreset.rawValue, forKey: SideloadSafeStorage.hdrSubtitlePresetKey)
            notifyChanged()
        }
    }

    public var subtitleFontSize: SubtitleFontSizePreset {
        didSet {
            guard oldValue != subtitleFontSize else { return }
            defaults.set(subtitleFontSize.scaleFactor, forKey: SideloadSafeStorage.subtitleFontScaleKey)
            notifyChanged()
        }
    }

    public var subtitleBoxOpacity: SubtitleBoxOpacityPreset {
        didSet {
            guard oldValue != subtitleBoxOpacity else { return }
            defaults.set(subtitleBoxOpacity.rawValue, forKey: SideloadSafeStorage.subtitleBoxOpacityKey)
            notifyChanged()
        }
    }

    public var dualLayerOverride: DualLayerOverrideMode {
        didSet {
            guard oldValue != dualLayerOverride else { return }
            defaults.set(dualLayerOverride.rawValue, forKey: SideloadSafeStorage.dualLayerOverrideKey)
            notifyChanged()
        }
    }

    public var speakerLayoutOverride: SpeakerLayoutOverrideMode {
        didSet {
            guard oldValue != speakerLayoutOverride else { return }
            defaults.set(speakerLayoutOverride.rawValue, forKey: SideloadSafeStorage.speakerLayoutOverrideKey)
            notifyChanged()
        }
    }

    /// Server-reported or room-resolved auto speaker layout (`7.1.4`, `5.1.2`, or `2.0`).
    public var roomAutoSpeakerLayout: String = "7.1.4"

    public var effectiveSpeakerLayout: String {
        speakerLayoutOverride == .auto ? roomAutoSpeakerLayout : speakerLayoutOverride.rawValue
    }

    public var autoPlayNextEpisode: Bool {
        didSet {
            guard oldValue != autoPlayNextEpisode else { return }
            defaults.set(autoPlayNextEpisode, forKey: SideloadSafeStorage.autoPlayNextEpisodeKey)
            notifyChanged()
        }
    }

    public var smartNordicSubtitleRule: Bool {
        didSet {
            guard oldValue != smartNordicSubtitleRule else { return }
            defaults.set(smartNordicSubtitleRule, forKey: SideloadSafeStorage.smartNordicSubtitleRuleKey)
            notifyChanged()
        }
    }

    public var showNerdHUD: Bool {
        didSet {
            guard oldValue != showNerdHUD else { return }
            defaults.set(showNerdHUD, forKey: SideloadSafeStorage.showNerdHUDKey)
        }
    }

    public var menuDisplayMode: MenuDisplayMode {
        didSet {
            guard oldValue != menuDisplayMode else { return }
            defaults.set(menuDisplayMode.rawValue, forKey: SideloadSafeStorage.menuDisplayModeKey)
        }
    }

    /// True when leaving playback keeps HDR/24p criteria active rather than immediately returning to SDR 60 Hz.
    public var keepDisplayModeInMenuAfterPlayback: Bool {
        menuDisplayMode != .sdr60Hz
    }

    public var lowResUpscaleMode: LowResUpscaleMode {
        didSet {
            guard oldValue != lowResUpscaleMode else { return }
            defaults.set(lowResUpscaleMode.rawValue, forKey: SideloadSafeStorage.lowResUpscaleModeKey)
        }
    }

    public var audioDelayMs: Int {
        didSet {
            let clamped = Self.clampAudioDelayMs(audioDelayMs)
            if clamped != audioDelayMs {
                audioDelayMs = clamped
                return
            }
            guard oldValue != audioDelayMs else { return }
            defaults.set(audioDelayMs, forKey: SideloadSafeStorage.audioDelayMsKey)
        }
    }

    public var audioEnhancement: AudioEnhancementMode {
        didSet {
            guard oldValue != audioEnhancement else { return }
            defaults.set(audioEnhancement.rawValue, forKey: SideloadSafeStorage.audioEnhancementModeKey)
        }
    }

    @ObservationIgnored public var onSyncRequested: ((TvDeviceOverrides) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var suppressSync: Bool = false

    public init(
        defaults: UserDefaults = .standard,
        memoryTier: DeviceMemoryTier = DeviceHardwareCapabilities.memoryProfile.tier
    ) {
        self.defaults = defaults

        let rawPreset = defaults.string(forKey: SideloadSafeStorage.hdrSubtitlePresetKey) ?? HDRSubtitlePreset.warm75.rawValue
        self.hdrSubtitlePreset = HDRSubtitlePreset(rawValue: rawPreset) ?? .warm75

        if defaults.object(forKey: SideloadSafeStorage.subtitleFontScaleKey) != nil {
            let savedScale = defaults.double(forKey: SideloadSafeStorage.subtitleFontScaleKey)
            self.subtitleFontSize = SubtitleFontSizePreset.fromScale(savedScale)
        } else {
            self.subtitleFontSize = .normal
        }

        let rawBox = defaults.string(forKey: SideloadSafeStorage.subtitleBoxOpacityKey) ?? SubtitleBoxOpacityPreset.none.rawValue
        self.subtitleBoxOpacity = SubtitleBoxOpacityPreset(rawValue: rawBox) ?? .none

        let rawDL = defaults.string(forKey: SideloadSafeStorage.dualLayerOverrideKey) ?? DualLayerOverrideMode.auto.rawValue
        self.dualLayerOverride = DualLayerOverrideMode(rawValue: rawDL) ?? .auto

        let rawSpk = defaults.string(forKey: SideloadSafeStorage.speakerLayoutOverrideKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedSpk = SpeakerLayoutOverrideMode.fromStored(rawSpk)
        self.speakerLayoutOverride = parsedSpk
        if parsedSpk == .auto, let rawSpk, rawSpk != SpeakerLayoutOverrideMode.auto.rawValue {
            defaults.set(SpeakerLayoutOverrideMode.auto.rawValue, forKey: SideloadSafeStorage.speakerLayoutOverrideKey)
        }

        self.autoPlayNextEpisode = defaults.object(forKey: SideloadSafeStorage.autoPlayNextEpisodeKey) as? Bool ?? true
        self.smartNordicSubtitleRule = defaults.object(forKey: SideloadSafeStorage.smartNordicSubtitleRuleKey) as? Bool ?? true
        self.showNerdHUD = defaults.object(forKey: SideloadSafeStorage.showNerdHUDKey) as? Bool ?? false
        if let rawMenuMode = defaults.string(forKey: SideloadSafeStorage.menuDisplayModeKey),
           let parsedMenuMode = MenuDisplayMode(rawValue: rawMenuMode) {
            self.menuDisplayMode = parsedMenuMode
        } else {
            self.menuDisplayMode = .sdr60Hz
        }
        if let rawUpscale = defaults.string(forKey: SideloadSafeStorage.lowResUpscaleModeKey),
           let savedUpscale = LowResUpscaleMode(rawValue: rawUpscale) {
            self.lowResUpscaleMode = savedUpscale
        } else {
            self.lowResUpscaleMode = LowResUpscaleMode.defaultMode(for: memoryTier)
        }
        if defaults.object(forKey: SideloadSafeStorage.audioDelayMsKey) != nil {
            self.audioDelayMs = Self.clampAudioDelayMs(defaults.integer(forKey: SideloadSafeStorage.audioDelayMsKey))
        } else {
            self.audioDelayMs = 0
        }
        if let rawEnhancement = defaults.string(forKey: SideloadSafeStorage.audioEnhancementModeKey),
           let parsedEnhancement = AudioEnhancementMode(rawValue: rawEnhancement) {
            self.audioEnhancement = parsedEnhancement
        } else {
            self.audioEnhancement = .reference
        }
    }

    public var audioDelaySeconds: Double {
        Double(audioDelayMs) / 1000.0
    }

    public func adjustAudioDelay(byMs deltaMs: Int) {
        audioDelayMs = PlaybackSyncTimingPolicy.stepAudioDelayMs(from: audioDelayMs, deltaMs: deltaMs)
    }

    public func resetAudioDelay() {
        audioDelayMs = 0
    }

    public func toDeviceOverrides() -> TvDeviceOverrides {
        TvDeviceOverrides(
            dualLayerOverride: dualLayerOverride.rawValue,
            speakerLayoutOverride: speakerLayoutOverride.rawValue,
            hdrSubtitlePreset: hdrSubtitlePreset.rawValue,
            subtitleFontScale: subtitleFontSize.scaleFactor,
            subtitleBoxOpacity: subtitleBoxOpacity.alpha,
            autoPlayNextEpisode: autoPlayNextEpisode,
            smartNordicSubtitleRule: smartNordicSubtitleRule
        )
    }

    public func adoptServerOverrides(_ ov: TvDeviceOverrides?) {
        guard let ov else { return }
        suppressSync = true
        defer { suppressSync = false }

        if let p = ov.hdrSubtitlePreset, let parsed = HDRSubtitlePreset(rawValue: p), parsed != hdrSubtitlePreset {
            hdrSubtitlePreset = parsed
        }
        if let s = ov.subtitleFontScale {
            let parsed = SubtitleFontSizePreset.fromScale(s)
            if parsed != subtitleFontSize {
                subtitleFontSize = parsed
            }
        }
        if let boxAlpha = ov.subtitleBoxOpacity {
            let parsed = SubtitleBoxOpacityPreset.fromAlpha(boxAlpha)
            if parsed != subtitleBoxOpacity {
                subtitleBoxOpacity = parsed
            }
        }
        if let dl = ov.dualLayerOverride, let parsed = DualLayerOverrideMode(rawValue: dl), parsed != dualLayerOverride {
            dualLayerOverride = parsed
        }
        if let spk = ov.speakerLayoutOverride {
            let cleanSpk = spk.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsed = SpeakerLayoutOverrideMode.fromStored(cleanSpk)
            if parsed != speakerLayoutOverride {
                speakerLayoutOverride = parsed
            } else if parsed == .auto {
                defaults.set(SpeakerLayoutOverrideMode.auto.rawValue, forKey: SideloadSafeStorage.speakerLayoutOverrideKey)
            }
        }
        if let autoNext = ov.autoPlayNextEpisode, autoNext != autoPlayNextEpisode {
            autoPlayNextEpisode = autoNext
        }
        if let smartRule = ov.smartNordicSubtitleRule, smartRule != smartNordicSubtitleRule {
            smartNordicSubtitleRule = smartRule
        }
    }

    public func buildAudioShaping(enhancement: AudioEnhancementMode) -> AudioShaping {
        let params = enhancement.shapingParameters(effectiveSpeakerLayout: effectiveSpeakerLayout)
        return AudioShaping(
            maxChannels: params.maxChannels,
            dialogueGainDB: params.dialogueGainDB,
            compressor: params.usesNightCompressor ? .night : nil,
            loudnessTargetLUFS: params.loudnessTargetLUFS,
            lfeMixDB: params.lfeMixDB
        )
    }

    private func notifyChanged() {
        guard !suppressSync else { return }
        onSyncRequested?(toDeviceOverrides())
    }
}
