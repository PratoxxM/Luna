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

public extension UpscaleScalerPolicy {
    var aetherScaler: UpscaleScaler {
        switch self {
        case .automatic:
            return .automatic
        case .lineArt:
            return .lineArt
        case .lanczos:
            return .lanczos
        }
    }
}

public extension ComfortPreferences {
    func buildAudioShaping(
        enhancement: AudioEnhancementMode,
        binaural: Bool = false,
        effectiveSpeakerLayoutOverride: String? = nil
    ) -> AudioShaping {
        let layout = effectiveSpeakerLayoutOverride ?? effectiveSpeakerLayout
        let params = enhancement.shapingParameters(effectiveSpeakerLayout: layout)
        return AudioShaping(
            maxChannels: params.maxChannels,
            dialogueGainDB: params.dialogueGainDB,
            compressor: params.usesNightCompressor ? .night : nil,
            loudnessTargetLUFS: params.loudnessTargetLUFS,
            lfeMixDB: params.lfeMixDB,
            binaural: binaural
        )
    }
}
