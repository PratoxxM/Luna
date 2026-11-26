import Foundation
import AetherBridge

extension PlayerQoSReporter {
    var isMetalFXActive: Bool {
        activeUpscale != nil && activeUpscale?.disabledReason == nil
    }

    var liveQualitySummaryBadge: String? {
        if let metalBadge = activeMetalFXBadge {
            return metalBadge
        }
        if let quality = host?.sessionController.activeSession?.selectedCandidate.humanQualitySummary,
           !quality.isEmpty {
            return quality
        }
        return nil
    }

    var activeMetalFXBadge: String? {
        guard isMetalFXActive else { return nil }
        let rawH: Int = {
            if sourceVideoHeight > 0 {
                return Int(sourceVideoHeight)
            }
            let upscaleHeight = Double(activeUpscale?.sourceSize.height ?? 1080)
            guard upscaleHeight.isFinite else { return 0 }
            return Int(exactly: upscaleHeight.rounded()) ?? 0
        }()
        let sourceLabel = rawH > 0 ? "\(rawH)p" : "SD/HD"
        if activeUpscale?.scaler == .lineArt || comfort.lowResUpscaleMode == .animeLineArt {
            return "\(sourceLabel) → 4K MetalFX (Animasjon)"
        }
        return "\(sourceLabel) → 4K MetalFX"
    }

    var videoFormatSummaryLine: String {
        var parts: [String] = []
        if sourceVideoHeight > 0 {
            parts.append(sourceVideoHeight >= 1800 ? "4K" : "\(sourceVideoHeight)p")
        }
        switch videoFormat {
        case .dolbyVision: parts.append("Dolby Vision")
        case .hdr10Plus: parts.append("HDR10+")
        case .hdr10: parts.append("HDR10")
        case .hlg: parts.append("HLG")
        case .sdr: parts.append("SDR")
        @unknown default: break
        }
        if let fps = sourceVideoFrameRate, fps.isFinite, fps > 0 {
            let rounded = (fps * 100).rounded() / 100
            if rounded.isFinite, rounded == rounded.rounded(), let intFps = Int(exactly: rounded) {
                parts.append("\(intFps)p")
            } else if rounded.isFinite {
                parts.append("\(LunaCopy.formatDecimal(rounded, decimals: 2))p")
            }
        }
        if let dec = activeVideoDecoder, !dec.isEmpty {
            parts.append(dec)
        }
        return parts.isEmpty ? "Video: Avspillingsklar" : "Video: " + parts.joined(separator: " · ")
    }

    var videoFormatBadge: String {
        switch videoFormat {
        case .dolbyVision:
            if sourceDVProfile == 7 {
                return (videoRoute == .software && dolbyVisionConversion == nil) ? "DV P7 FEL" : "DV P7"
            }
            if sourceDVProfile == 8 || dolbyVisionConversion == .profile7ToProfile81 {
                return "DV P8"
            }
            if let p = sourceDVProfile {
                return "DV P\(p)"
            }
            return "Dolby Vision"
        case .hdr10Plus: return "HDR10+"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .sdr: return sourceVideoHeight >= 2000 ? "4K SDR" : "SDR"
        }
    }

    var audioFormatBadge: String {
        if comfort.speakerLayoutOverride == .stereo {
            return "Stereo 2.0"
        }
        let tracks = host?.trackController.audioTracks ?? []
        let activeIdx = host?.trackController.activeAudioTrackIndex
        let activeTrack = tracks.first(where: { $0.id == activeIdx })
        let configuredLayout = effectiveSpeakerLayoutLabel(isDTSX: activeTrack?.isDTSX == true)
        if let activeTrack {
            if activeTrack.isAtmos { return "\(configuredLayout) Atmos" }
            if activeTrack.isDTSX { return "\(configuredLayout) DTS:X" }
            let codecUpper = activeTrack.codec.uppercased()
            if codecUpper.contains("TRUEHD") {
                return "TrueHD \(activeTrack.channelLayout ?? "7.1")"
            }
            if codecUpper.contains("DTS") || codecUpper.contains("DCA") {
                return "\(activeTrack.profile ?? "DTS-HD") \(activeTrack.channelLayout ?? "")"
                    .trimmingCharacters(in: .whitespaces)
            }
            if audioDelivery == .bridged {
                return "LPCM \(activeTrack.channelLayout ?? "")".trimmingCharacters(in: .whitespaces)
            }
            return "\(codecUpper) \(activeTrack.channelLayout ?? "")".trimmingCharacters(in: .whitespaces)
        }
        return configuredLayout
    }

    var sessionRoomAutoLayout: String {
        let session = host?.sessionController.activeSession
        if let lay = session?.aetherConfig.objectAudioRendering?.layout, !lay.isEmpty {
            return lay
        }
        if session?.hardwareProfile == HardwareProfilePreset.hdr10512.rawValue {
            return "5.1.2"
        }
        return "7.1.4"
    }

    func effectiveSpeakerLayoutLabel(isDTSX: Bool) -> String {
        switch comfort.speakerLayoutOverride {
        case .stereo: return "Stereo 2.0"
        case .atmos512: return isDTSX ? "7.1.4" : "5.1.2"
        case .atmos714: return "7.1.4"
        case .auto:
            let base = sessionRoomAutoLayout
            return (base == "5.1.2" && isDTSX) ? "7.1.4" : base
        }
    }
}
