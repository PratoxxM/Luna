import SwiftUI
import AetherBridge

public enum HDRSubtitlePreset: String, CaseIterable, Identifiable, Sendable {
    case white100 = "white_100"
    case warm75 = "warm_75"
    case warm60 = "warm_60"
    case soft50 = "soft_50"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .white100: return "100 % Hvit"
        case .warm75: return "75 % Varmhvit"
        case .warm60: return "60 % Dempet kveld"
        case .soft50: return "50 % Nattkino"
        }
    }

    public var settingsDescription: String {
        switch self {
        case .white100:
            return "Full sRGB/HDR-grafikkhvit (~203 nits)"
        case .warm75:
            return "Anbefalt for OLED/HDR — behagelig varmhvit uten å blende i mørke scener"
        case .warm60:
            return "Mykere varmtone for kveldsvisning i mørkt rom"
        case .soft50:
            return "Maksimal øyekomfort i helt mørklagt hjemmekino"
        }
    }

    /// Foreground RGB multipliers used when `videoFormat != .sdr`.
    /// In `.sdr`, subtitles remain crisp standard white `(1.0, 1.0, 1.0)`.
    public var hdrRGB: (r: Double, g: Double, b: Double) {
        switch self {
        case .white100: return (1.00, 1.00, 1.00)
        case .warm75:   return (0.76, 0.72, 0.65)
        case .warm60:   return (0.62, 0.58, 0.52)
        case .soft50:   return (0.50, 0.47, 0.42)
        }
    }

    public func foregroundColor(isHDR: Bool) -> Color {
        guard isHDR else { return .white }
        let c = hdrRGB
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// GPU `.colorMultiply` tint for PGS/DVB bitmap cues:
    /// multiplying black outline pixels `(0, 0, 0, α)` yields `(0, 0, 0, α)` (100 % jet black),
    /// while bright white glyph fills `(1, 1, 1, α)` dim smoothly to warm white.
    public func bitmapMultiplyColor(isHDR: Bool) -> Color {
        guard isHDR else { return .white }
        let c = hdrRGB
        return Color(red: c.r, green: c.g, blue: c.b)
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
    case l714 = "7.1.4"
    case l512 = "5.1.2"
    case stereo = "2.0"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .auto: return "Auto fra romprofil"
        case .l714: return "7.1.4 Objektlyd"
        case .l512: return "5.1.2 Objektlyd"
        case .stereo: return "Stereo 2.0"
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
        case .reference: return "Ubehandlet dynamikk & objektlyd"
        case .dialogueLift: return "+4 dB senterkanal"
        case .nightMode: return "Myk kompressor + tydelig tale"
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
        case .auto: return "Auto MetalFX"
        case .animeLineArt: return "Anime & Strek"
        }
    }

    public var shortDescription: String {
        switch self {
        case .off: return "Nativ Apple TV-skalering"
        case .auto: return "Skarp oppskalering for SD / 720p / 1080p"
        case .animeLineArt: return "Linjekunst-skalerer for animasjon og anime"
        }
    }
}

@MainActor
public final class ComfortPreferences: ObservableObject {
    @Published public var hdrSubtitlePreset: HDRSubtitlePreset {
        didSet {
            guard oldValue != hdrSubtitlePreset else { return }
            defaults.set(hdrSubtitlePreset.rawValue, forKey: SideloadSafeStorage.hdrSubtitlePresetKey)
            notifyChanged()
        }
    }

    @Published public var subtitleFontSize: SubtitleFontSizePreset {
        didSet {
            guard oldValue != subtitleFontSize else { return }
            defaults.set(subtitleFontSize.scaleFactor, forKey: SideloadSafeStorage.subtitleFontScaleKey)
            notifyChanged()
        }
    }

    @Published public var subtitleBoxOpacity: SubtitleBoxOpacityPreset {
        didSet {
            guard oldValue != subtitleBoxOpacity else { return }
            defaults.set(subtitleBoxOpacity.rawValue, forKey: SideloadSafeStorage.subtitleBoxOpacityKey)
            notifyChanged()
        }
    }

    @Published public var dualLayerOverride: DualLayerOverrideMode {
        didSet {
            guard oldValue != dualLayerOverride else { return }
            defaults.set(dualLayerOverride.rawValue, forKey: SideloadSafeStorage.dualLayerOverrideKey)
            notifyChanged()
        }
    }

    @Published public var speakerLayoutOverride: SpeakerLayoutOverrideMode {
        didSet {
            guard oldValue != speakerLayoutOverride else { return }
            defaults.set(speakerLayoutOverride.rawValue, forKey: SideloadSafeStorage.speakerLayoutOverrideKey)
            notifyChanged()
        }
    }

    @Published public var autoPlayNextEpisode: Bool {
        didSet {
            guard oldValue != autoPlayNextEpisode else { return }
            defaults.set(autoPlayNextEpisode, forKey: SideloadSafeStorage.autoPlayNextEpisodeKey)
            notifyChanged()
        }
    }

    @Published public var smartNordicSubtitleRule: Bool {
        didSet {
            guard oldValue != smartNordicSubtitleRule else { return }
            defaults.set(smartNordicSubtitleRule, forKey: SideloadSafeStorage.smartNordicSubtitleRuleKey)
            notifyChanged()
        }
    }

    @Published public var showNerdHUD: Bool {
        didSet {
            guard oldValue != showNerdHUD else { return }
            defaults.set(showNerdHUD, forKey: SideloadSafeStorage.showNerdHUDKey)
        }
    }

    @Published public var lowResUpscaleMode: LowResUpscaleMode {
        didSet {
            guard oldValue != lowResUpscaleMode else { return }
            defaults.set(lowResUpscaleMode.rawValue, forKey: SideloadSafeStorage.lowResUpscaleModeKey)
        }
    }

    public var onSyncRequested: ((TvDeviceOverrides) -> Void)?

    private let defaults: UserDefaults
    private var suppressSync: Bool = false

    public init(defaults: UserDefaults = .standard) {
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

        let rawSpk = defaults.string(forKey: SideloadSafeStorage.speakerLayoutOverrideKey) ?? SpeakerLayoutOverrideMode.auto.rawValue
        self.speakerLayoutOverride = SpeakerLayoutOverrideMode(rawValue: rawSpk) ?? .auto

        self.autoPlayNextEpisode = defaults.object(forKey: SideloadSafeStorage.autoPlayNextEpisodeKey) as? Bool ?? true
        self.smartNordicSubtitleRule = defaults.object(forKey: SideloadSafeStorage.smartNordicSubtitleRuleKey) as? Bool ?? true
        self.showNerdHUD = defaults.object(forKey: SideloadSafeStorage.showNerdHUDKey) as? Bool ?? false
        let rawUpscale = defaults.string(forKey: SideloadSafeStorage.lowResUpscaleModeKey) ?? LowResUpscaleMode.off.rawValue
        self.lowResUpscaleMode = LowResUpscaleMode(rawValue: rawUpscale) ?? .off
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
        if let spk = ov.speakerLayoutOverride, let parsed = SpeakerLayoutOverrideMode(rawValue: spk), parsed != speakerLayoutOverride {
            speakerLayoutOverride = parsed
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
                lfeMixDB: -6.0
            )
        }
    }

    private func notifyChanged() {
        guard !suppressSync else { return }
        onSyncRequested?(toDeviceOverrides())
    }
}
