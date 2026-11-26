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

public extension ComfortPreferences {
    func buildAudioShaping(enhancement: AudioEnhancementMode) -> AudioShaping {
        let params = enhancement.shapingParameters(effectiveSpeakerLayout: effectiveSpeakerLayout)
        return AudioShaping(
            maxChannels: params.maxChannels,
            dialogueGainDB: params.dialogueGainDB,
            compressor: params.usesNightCompressor ? .night : nil,
            loudnessTargetLUFS: params.loudnessTargetLUFS,
            lfeMixDB: params.lfeMixDB
        )
    }
}
