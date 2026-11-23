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

public enum SubtitleFontSizePreset: String, CaseIterable, Identifiable, Sendable {
    case small
    case normal
    case large

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .small: return "Liten"
        case .normal: return "Normal"
        case .large: return "Stor"
        }
    }

    public var scaleFactor: Double {
        switch self {
        case .small: return 0.85
        case .normal: return 1.00
        case .large: return 1.20
        }
    }

    public var pointSize: CGFloat {
        switch self {
        case .small: return 36
        case .normal: return 42
        case .large: return 50
        }
    }

    public static func fromScale(_ scale: Double) -> SubtitleFontSizePreset {
        if scale <= 0.91 { return .small }
        if scale >= 1.10 { return .large }
        return .normal
    }
}

public enum SubtitleBoxOpacityPreset: String, CaseIterable, Identifiable, Sendable {
    case none
    case subtle35
    case cinema60

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .none: return "Ingen boks"
        case .subtle35: return "Diskret 35 %"
        case .cinema60: return "Tydelig 60 %"
        }
    }

    public var alpha: Double {
        switch self {
        case .none: return 0.0
        case .subtle35: return 0.35
        case .cinema60: return 0.60
        }
    }

    public static func fromAlpha(_ alpha: Double) -> SubtitleBoxOpacityPreset {
        if alpha <= 0.1 { return .none }
        if alpha >= 0.5 { return .cinema60 }
        return .subtle35
    }
}

public enum DualLayerOverrideMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case forceOn = "force_on"
    case forceOff = "force_off"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .auto: return "Auto fra romprofil"
        case .forceOn: return "Tving P7 FEL på"
        case .forceOff: return "Tving HDR10-baselag"
        }
    }
}

public enum SpeakerLayoutOverrideMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case atmos512 = "5.1.2"
    case atmos714 = "7.1.4"
    case stereo = "2.0"

    public static let quickPanelCases: [SpeakerLayoutOverrideMode] = [.auto, .atmos512, .atmos714]

    public var id: String { rawValue }

    public var quickPillTitle: String {
        switch self {
        case .auto: return "Auto"
        case .atmos512: return "5.1.2"
        case .atmos714: return "7.1.4"
        case .stereo: return "Stereo 2.0"
        }
    }

    public var displayTitle: String {
        displayTitle(forHardwareProfile: HardwareProfilePreset.dvFel714.rawValue)
    }

    public func displayTitle(forHardwareProfile hardwareProfile: String) -> String {
        switch self {
        case .auto:
            let norm = hardwareProfile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return norm == HardwareProfilePreset.hdr10512.rawValue ? "Auto (5.1.2)" : "Auto (7.1.4)"
        case .atmos512:
            return "5.1.2"
        case .atmos714:
            return "7.1.4"
        case .stereo:
            return "Stereo 2.0 (TV-høyttalere)"
        }
    }

    public func headerSummary(forAutoLayout autoLayout: String) -> String {
        switch self {
        case .auto:
            return "Høyttaleroppsett · Auto (\(autoLayout))"
        case .atmos512:
            return "Høyttaleroppsett · 5.1.2"
        case .atmos714:
            return "Høyttaleroppsett · 7.1.4"
        case .stereo:
            return "Høyttaleroppsett · Stereo 2.0"
        }
    }

    public static func fromStored(_ raw: String?) -> SpeakerLayoutOverrideMode {
        let clean = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "5.1.2", "512":
            return .atmos512
        case "7.1.4", "714":
            return .atmos714
        case "2.0", "stereo":
            return .stereo
        default:
            return .auto
        }
    }
}

public enum MenuDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case sdr60Hz = "sdr_60hz"
    case preserveHDR60HzQMS = "hdr_60hz_qms"
    case preserveExactMatch = "exact_match"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .sdr60Hz: return "Standard SDR 60 Hz"
        case .preserveHDR60HzQMS: return "Behold HDR i 60 Hz (QMS)"
        case .preserveExactMatch: return "Behold filmens eksakte skjermmodus"
        }
    }

    public var shortDescription: String {
        switch self {
        case .sdr60Hz:
            return "Går tilbake til SDR 60 Hz i menyen (anbefalt for skjermer uten QMS)."
        case .preserveHDR60HzQMS:
            return "Beholder HDR/DV og skifter sømløst 24p → 60 Hz uten HDMI-blink på QMS-skjermer."
        case .preserveExactMatch:
            return "Beholder filmens nøyaktige 24p/HDR-modus til appen legges i bakgrunnen."
        }
    }
}

public enum AudioEnhancementMode: String, CaseIterable, Identifiable, Sendable {
    case reference
    case dialogueLift
    case nightMode

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .reference: return "Ren kino"
        case .dialogueLift: return "Dialogløft"
        case .nightMode: return "Nattmodus"
        }
    }

    public var subtitle: String {
        switch self {
        case .reference: return "Ubehandlet dynamikk og objektlyd"
        case .dialogueLift: return "+4 dB senterkanal"
        case .nightMode: return "Myk kompressor og tydelig tale"
        }
    }
}

public enum LowResUpscaleMode: String, CaseIterable, Identifiable, Sendable {
    case off = "off"
    case auto = "auto"
    case animeLineArt = "line_art"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .off: return "Av"
        case .auto: return "Auto"
        case .animeLineArt: return "Animasjon"
        }
    }

    public var shortDescription: String {
        switch self {
        case .off: return "Standard tvOS-skalering uten MetalFX."
        case .auto: return "Kun < 1080p 8-bit SDR · 4K og HDR urørt."
        case .animeLineArt: return "Anime4K 2× linjekunst for ≤ 1080p SDR."
        }
    }

    public static func defaultMode(for tier: DeviceMemoryTier) -> LowResUpscaleMode {
        tier == .high2026 ? .auto : .off
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
        audioDelayMs = Self.clampAudioDelayMs(audioDelayMs + deltaMs)
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
        let isStereo = (speakerLayoutOverride == .stereo)
        let maxCh: Int? = isStereo ? 2 : nil
        let stereoLfeDB: Double? = isStereo ? -6.0 : nil
        switch enhancement {
        case .reference:
            return AudioShaping(
                maxChannels: maxCh,
                dialogueGainDB: 0,
                compressor: nil,
                loudnessTargetLUFS: nil,
                lfeMixDB: stereoLfeDB
            )
        case .dialogueLift:
            return AudioShaping(
                maxChannels: maxCh,
                dialogueGainDB: 4.0,
                compressor: nil,
                loudnessTargetLUFS: nil,
                lfeMixDB: stereoLfeDB
            )
        case .nightMode:
            return AudioShaping(
                maxChannels: maxCh,
                dialogueGainDB: 3.5,
                compressor: .night,
                loudnessTargetLUFS: -20.0,
                lfeMixDB: stereoLfeDB
            )
        }
    }

    private func notifyChanged() {
        guard !suppressSync else { return }
        onSyncRequested?(toDeviceOverrides())
    }
}
