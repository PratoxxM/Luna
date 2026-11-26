import Foundation

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

    public var pointSizeValue: Double {
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
        let autoLayout = Self.resolveAutoSpeakerLayout(
            speakerLayout: nil,
            equipmentLabel: nil,
            hardwareProfile: hardwareProfile,
            roomName: nil
        )
        return displayTitle(forAutoLayout: autoLayout)
    }

    public func displayTitle(forAutoLayout autoLayout: String) -> String {
        switch self {
        case .auto:
            let label = autoLayout == "2.0" ? "Stereo 2.0" : autoLayout
            return "Auto (\(label))"
        case .atmos512:
            return "5.1.2"
        case .atmos714:
            return "7.1.4"
        case .stereo:
            return "Stereo 2.0 (TV-høyttalere)"
        }
    }

    public static func resolveAutoSpeakerLayout(
        speakerLayout: String? = nil,
        equipmentLabel: String? = nil,
        hardwareProfile: String,
        roomName: String? = nil
    ) -> String {
        let cleanLayout = (speakerLayout ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch cleanLayout {
        case "2.0", "stereo":
            return "2.0"
        case "5.1.2", "512":
            return "5.1.2"
        case "7.1.4", "714":
            return "7.1.4"
        default:
            break
        }

        let cleanEquip = (equipmentLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanEquip.contains("2.0") || cleanEquip.contains("stereo") {
            return "2.0"
        }
        if cleanEquip.contains("5.1.2") {
            return "5.1.2"
        }
        if cleanEquip.contains("7.1.4") {
            return "7.1.4"
        }

        let normProfile = hardwareProfile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normProfile == HardwareProfilePreset.hdr10512.rawValue
            || normProfile.contains("512")
            || normProfile.contains("living") {
            return "5.1.2"
        }
        if normProfile == HardwareProfilePreset.dvFel714.rawValue
            || normProfile.contains("714")
            || normProfile.contains("cinema") {
            return "7.1.4"
        }

        let normRoom = (roomName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normRoom.contains("stua") && !normRoom.contains("kjeller") {
            return "5.1.2"
        }
        return "7.1.4"
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

public struct AudioShapingParameters: Equatable, Sendable {
    public let maxChannels: Int?
    public let dialogueGainDB: Double
    public let usesNightCompressor: Bool
    public let loudnessTargetLUFS: Double?
    public let lfeMixDB: Double?

    public init(
        maxChannels: Int?,
        dialogueGainDB: Double,
        usesNightCompressor: Bool,
        loudnessTargetLUFS: Double?,
        lfeMixDB: Double?
    ) {
        self.maxChannels = maxChannels
        self.dialogueGainDB = dialogueGainDB
        self.usesNightCompressor = usesNightCompressor
        self.loudnessTargetLUFS = loudnessTargetLUFS
        self.lfeMixDB = lfeMixDB
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

    public func shapingParameters(effectiveSpeakerLayout: String) -> AudioShapingParameters {
        let isStereo = (effectiveSpeakerLayout.trimmingCharacters(in: .whitespacesAndNewlines) == "2.0")
        let maxCh: Int? = isStereo ? 2 : nil
        let stereoLfeDB: Double? = isStereo ? -6.0 : nil
        switch self {
        case .reference:
            return AudioShapingParameters(
                maxChannels: maxCh,
                dialogueGainDB: 0,
                usesNightCompressor: false,
                loudnessTargetLUFS: nil,
                lfeMixDB: stereoLfeDB
            )
        case .dialogueLift:
            return AudioShapingParameters(
                maxChannels: maxCh,
                dialogueGainDB: 4.0,
                usesNightCompressor: false,
                loudnessTargetLUFS: nil,
                lfeMixDB: stereoLfeDB
            )
        case .nightMode:
            return AudioShapingParameters(
                maxChannels: maxCh,
                dialogueGainDB: 3.5,
                usesNightCompressor: true,
                loudnessTargetLUFS: -20.0,
                lfeMixDB: stereoLfeDB
            )
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
