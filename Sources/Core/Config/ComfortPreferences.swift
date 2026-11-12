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

@MainActor
public final class ComfortPreferences: ObservableObject {
    @Published public var hdrSubtitlePreset: HDRSubtitlePreset {
        didSet {
            defaults.set(hdrSubtitlePreset.rawValue, forKey: SideloadSafeStorage.hdrSubtitlePresetKey)
            notifyChanged()
        }
    }

    @Published public var subtitleFontSize: SubtitleFontSizePreset {
        didSet {
            defaults.set(subtitleFontSize.scaleFactor, forKey: SideloadSafeStorage.subtitleFontScaleKey)
            notifyChanged()
        }
    }

    @Published public var subtitleBoxOpacity: SubtitleBoxOpacityPreset {
        didSet {
            defaults.set(subtitleBoxOpacity.rawValue, forKey: SideloadSafeStorage.subtitleBoxOpacityKey)
        }
    }

    @Published public var dualLayerOverride: DualLayerOverrideMode {
        didSet {
            defaults.set(dualLayerOverride.rawValue, forKey: SideloadSafeStorage.dualLayerOverrideKey)
            notifyChanged()
        }
    }

    @Published public var speakerLayoutOverride: SpeakerLayoutOverrideMode {
        didSet {
            defaults.set(speakerLayoutOverride.rawValue, forKey: SideloadSafeStorage.speakerLayoutOverrideKey)
            notifyChanged()
        }
    }

    @Published public var autoPlayNextEpisode: Bool {
        didSet {
            defaults.set(autoPlayNextEpisode, forKey: SideloadSafeStorage.autoPlayNextEpisodeKey)
            notifyChanged()
        }
    }

    @Published public var smartNordicSubtitleRule: Bool {
        didSet {
            defaults.set(smartNordicSubtitleRule, forKey: SideloadSafeStorage.smartNordicSubtitleRuleKey)
            notifyChanged()
        }
    }

    @Published public var showNerdHUD: Bool {
        didSet {
            defaults.set(showNerdHUD, forKey: SideloadSafeStorage.showNerdHUDKey)
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

        let rawBox = defaults.string(forKey: SideloadSafeStorage.subtitleBoxOpacityKey) ?? SubtitleBoxOpacityPreset.subtle35.rawValue
        self.subtitleBoxOpacity = SubtitleBoxOpacityPreset(rawValue: rawBox) ?? .subtle35

        let rawDL = defaults.string(forKey: SideloadSafeStorage.dualLayerOverrideKey) ?? DualLayerOverrideMode.auto.rawValue
        self.dualLayerOverride = DualLayerOverrideMode(rawValue: rawDL) ?? .auto

        let rawSpk = defaults.string(forKey: SideloadSafeStorage.speakerLayoutOverrideKey) ?? SpeakerLayoutOverrideMode.auto.rawValue
        self.speakerLayoutOverride = SpeakerLayoutOverrideMode(rawValue: rawSpk) ?? .auto

        self.autoPlayNextEpisode = defaults.object(forKey: SideloadSafeStorage.autoPlayNextEpisodeKey) as? Bool ?? true
        self.smartNordicSubtitleRule = defaults.object(forKey: SideloadSafeStorage.smartNordicSubtitleRuleKey) as? Bool ?? true
        self.showNerdHUD = defaults.object(forKey: SideloadSafeStorage.showNerdHUDKey) as? Bool ?? false
    }

    public func toDeviceOverrides() -> TvDeviceOverrides {
        TvDeviceOverrides(
            dualLayerOverride: dualLayerOverride.rawValue,
            speakerLayoutOverride: speakerLayoutOverride.rawValue,
            hdrSubtitlePreset: hdrSubtitlePreset.rawValue,
            subtitleFontScale: subtitleFontSize.scaleFactor,
            autoPlayNextEpisode: autoPlayNextEpisode,
            smartNordicSubtitleRule: smartNordicSubtitleRule
        )
    }

    public func adoptServerOverrides(_ ov: TvDeviceOverrides?) {
        guard let ov else { return }
        suppressSync = true
        defer { suppressSync = false }

        if let p = ov.hdrSubtitlePreset, let parsed = HDRSubtitlePreset(rawValue: p) {
            hdrSubtitlePreset = parsed
        }
        if let s = ov.subtitleFontScale {
            subtitleFontSize = SubtitleFontSizePreset.fromScale(s)
        }
        if let dl = ov.dualLayerOverride, let parsed = DualLayerOverrideMode(rawValue: dl) {
            dualLayerOverride = parsed
        }
        if let spk = ov.speakerLayoutOverride, let parsed = SpeakerLayoutOverrideMode(rawValue: spk) {
            speakerLayoutOverride = parsed
        }
        if let autoNext = ov.autoPlayNextEpisode {
            autoPlayNextEpisode = autoNext
        }
        if let smartRule = ov.smartNordicSubtitleRule {
            smartNordicSubtitleRule = smartRule
        }
    }

    public func buildAudioShaping(enhancement: AudioEnhancementMode) -> AudioShaping {
        let maxCh: Int? = (speakerLayoutOverride == .stereo) ? 2 : nil
        switch enhancement {
        case .reference:
            return AudioShaping(maxChannels: maxCh, dialogueGainDB: 0, compressor: nil)
        case .dialogueLift:
            return AudioShaping(maxChannels: maxCh, dialogueGainDB: 4.0, compressor: nil)
        case .nightMode:
            return AudioShaping(maxChannels: maxCh, dialogueGainDB: 3.5, compressor: .night)
        }
    }

    private func notifyChanged() {
        guard !suppressSync else { return }
        onSyncRequested?(toDeviceOverrides())
    }
}

/// Automatic language comfort rules:
/// - Rule A: Norwegian audio -> subtitles off (unless a Norwegian forced track exists).
/// - Rule B: Foreign audio -> best Norwegian subtitle (non-SDH preferred, text preferred over bitmap),
///   falling back to English if Norwegian is unavailable.
@MainActor
public enum SmartTrackRuleEngine {
    public enum Decision: Equatable, Sendable {
        case clearSubtitles
        case selectTrack(Int)
        case keepCurrent
    }

    public static func evaluate(
        activeAudio: TrackInfo?,
        subtitleTracks: [TrackInfo]
    ) -> Decision {
        guard let activeAudio else { return .keepCurrent }
        let audioLang = normalizeLanguage(activeAudio.language, fallbackName: activeAudio.name)

        // Rule A: Norwegian dialogue -> turn off full subtitles, keep forced translations only
        if audioLang == "nob" {
            if let forcedNo = subtitleTracks.first(where: {
                $0.isForced && normalizeLanguage($0.language, fallbackName: $0.name) == "nob"
            }) {
                return .selectTrack(forcedNo.id)
            }
            return .clearSubtitles
        }

        // Rule B: Foreign dialogue -> prefer Norwegian, fallback to English
        if let bestNo = pickBestSubtitle(forLanguage: "nob", in: subtitleTracks) {
            return .selectTrack(bestNo.id)
        }
        if let bestEn = pickBestSubtitle(forLanguage: "eng", in: subtitleTracks) {
            return .selectTrack(bestEn.id)
        }
        return .keepCurrent
    }

    public static func normalizeLanguage(_ rawCode: String?, fallbackName: String = "") -> String? {
        let code = (rawCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["no", "nb", "nn", "nor", "nob", "nno", "norwegian", "norsk", "bokmål", "nynorsk"].contains(code) {
            return "nob"
        }
        if ["en", "eng", "english", "engelsk"].contains(code) {
            return "eng"
        }
        if ["sv", "swe", "swedish", "svensk"].contains(code) {
            return "swe"
        }
        if ["da", "dan", "danish", "dansk"].contains(code) {
            return "dan"
        }

        let nameLower = fallbackName.lowercased()
        if nameLower.contains("norsk") || nameLower.contains("norwegian") || nameLower.contains("bokmål") {
            return "nob"
        }
        if nameLower.contains("english") || nameLower.contains("engelsk") {
            return "eng"
        }
        return code.isEmpty ? nil : code
    }

    private static func pickBestSubtitle(forLanguage targetLang: String, in tracks: [TrackInfo]) -> TrackInfo? {
        let candidates = tracks.filter {
            normalizeLanguage($0.language, fallbackName: $0.name) == targetLang && !$0.isCommentary
        }
        guard !candidates.isEmpty else { return nil }

        return candidates.max { a, b in
            scoreSubtitle(a) < scoreSubtitle(b)
        }
    }

    private static func scoreSubtitle(_ track: TrackInfo) -> Int {
        var score = 0
        // Full dialogue subtitles strongly beat forced-only tracks for foreign audio
        if !track.isForced {
            score += 100
        }
        // Clean standard captions beat SDH/HI when both exist
        if !track.isHearingImpaired && !isNameSDH(track.name) {
            score += 40
        }
        // Crisp scalable text subtitles (.srt / ASS) slightly beat bitmap PGS when both exist
        let codecLower = track.codec.lowercased()
        let isBitmap = codecLower.contains("pgs") || codecLower.contains("dvd") || codecLower.contains("dvb")
        if !isBitmap {
            score += 18
        }
        if track.isExternal {
            score += 8
        }
        if track.isDefault {
            score += 4
        }
        return score
    }

    private static func isNameSDH(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("sdh") || lower.contains("hearing") || lower.contains("cc")
    }
}
