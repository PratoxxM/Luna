import SwiftUI
import AetherBridge

/// Isolated 1 Hz diagnostic HUD (`740 pt` wide, `184 pt` single-line key column)
/// observing `engine.diagnostics.$liveTelemetry` & `$sessionCacheStatus` in a leaf view
/// so telemetry ticks never re-render the video player shell.
struct NerdHUDView: View {
    static let cardWidth: CGFloat = 740
    static let keyColumnWidth: CGFloat = 184
    static let standardRowKeys: [String] = [
        "Video",
        "HDR / Rute",
        "Dekoder",
        "Skalering",
        "Lydkjede",
        "Bitrate",
        "Nett / Buffer",
        "Utgave / Minne",
    ]

    let engine: AetherEngine
    let viewModel: PlayerViewModel

    @State private var telemetry: LiveTelemetry?
    @State private var cacheStatus: SessionCacheStatus = .inactive

    static func formatSessionCacheBytes(_ currentForwardBytes: Int64, isInactive: Bool = false) -> String? {
        guard !isInactive, currentForwardBytes > 0 else { return nil }
        let mib = Double(currentForwardBytes) / 1_048_576.0
        return "+\(LunaCopy.formatDecimal(mib)) MiB \(LunaCopy.ramBufferTitle)"
    }

    static func formatSessionCacheLabel(_ status: SessionCacheStatus) -> String? {
        formatSessionCacheBytes(Int64(clamping: status.currentForwardBytes), isInactive: status == .inactive)
    }

    var body: some View {
        let qos = viewModel.qosReporter
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LunaTheme.emerald)
                    .frame(width: 8, height: 8)
                Text("Teknisk oversikt")
                    .font(LunaTheme.Font.badge)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(1)
            }

            hudRow("Video", value: videoSummary)
            hudRow("HDR / Rute", value: "\(qos.videoFormatBadge) · \(qos.videoRoute.rawValue)")
            hudRow("Dekoder", value: decoderSummary)
            hudRow("Skalering", value: upscaleSummary)
            hudRow("Lydkjede", value: audioSummary)
            if let obj = telemetry?.objectAudio {
                hudRow("Objektlyd", value: "\(obj.layout.rawValue) · \(obj.activeObjects)/\(obj.objects) obj (\(obj.elevatedObjects) høyde)")
            }
            hudRow("Bitrate", value: bitrateSummary)
            hudRow("Nett / Buffer", value: bufferAndNetworkSummary)
            hudRow("Utgave / Minne", value: editionAndMemorySummary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: Self.cardWidth, alignment: .leading)
        .lunaCinemaGlassSurface(
            cornerRadius: LunaTokens.Radius.poster,
            topEdgeColor: LunaTokens.Edge.top2,
            sideEdgeColor: .clear,
            shadowColor: LunaTheme.pureBlack.opacity(0.42),
            shadowRadius: 10,
            shadowY: 4
        )
        .allowsHitTesting(false)
        .onReceive(engine.diagnostics.$liveTelemetry) { telemetry = $0 }
        .onReceive(engine.diagnostics.$sessionCacheStatus) { nextStatus in
            if cacheStatus != nextStatus {
                cacheStatus = nextStatus
            }
        }
    }

    private var videoSummary: String {
        let qos = viewModel.qosReporter
        let codec = (qos.sourceVideoCodecName ?? "hevc").uppercased()
        let w = qos.sourceVideoWidth
        let h = qos.sourceVideoHeight
        let res = (w > 0 && h > 0) ? "\(w)×\(h)" : "Auto"
        let fpsVal = telemetry?.observedFps ?? qos.sourceVideoFrameRate
        let fps = fpsVal.map {
            String(format: "%.3g fps", locale: Locale(identifier: "en_US_POSIX"), $0).replacingOccurrences(of: ".", with: ",")
        } ?? "-"
        return "\(codec) · \(res) @ \(fps)"
    }

    private var decoderSummary: String {
        let qos = viewModel.qosReporter
        let vDec = qos.activeVideoDecoder ?? (qos.videoRoute == .software ? "FFmpeg SW" : "VideoToolbox HW")
        let dropped = telemetry?.droppedFrameCount ?? 0
        return "\(vDec) · \(dropped) mistet"
    }

    private static func safeRoundedInt(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded())
    }

    static func upscaleSummary(
        activeUpscale: UpscaleStatus?,
        lowResUpscaleMode: LowResUpscaleMode,
        upscalesFullHDVideo: Bool,
        videoFormat: VideoFormat,
        sourceVideoWidth: Int32,
        sourceVideoHeight: Int32
    ) -> String {
        let activeInfo: ActiveUpscaleSummaryInfo? = activeUpscale.map { up in
            let scalerPolicy: UpscaleScalerPolicy
            if up.scaler == .lineArt {
                scalerPolicy = .lineArt
            } else if up.scaler == .lanczos {
                scalerPolicy = .lanczos
            } else {
                scalerPolicy = .automatic
            }
            return ActiveUpscaleSummaryInfo(
                sourceWidth: safeRoundedInt(Double(up.sourceSize.width)) ?? 0,
                sourceHeight: safeRoundedInt(Double(up.sourceSize.height)) ?? 0,
                targetWidth: safeRoundedInt(Double(up.targetSize.width)) ?? 0,
                targetHeight: safeRoundedInt(Double(up.targetSize.height)) ?? 0,
                scaler: scalerPolicy,
                mlScale: up.mlScale.map(Double.init),
                isDegraded: up.degraded
            )
        }
        return UpscaleSummaryFormatter.summary(
            activeUpscale: activeInfo,
            disabledReason: activeUpscale?.disabledReason,
            lowResUpscaleMode: lowResUpscaleMode,
            upscalesFullHDVideo: upscalesFullHDVideo,
            isSDR: videoFormat == .sdr,
            sourceVideoWidth: Int(sourceVideoWidth),
            sourceVideoHeight: Int(sourceVideoHeight)
        )
    }

    private var upscaleSummary: String {
        let qos = viewModel.qosReporter
        return Self.upscaleSummary(
            activeUpscale: qos.activeUpscale,
            lowResUpscaleMode: viewModel.comfort.lowResUpscaleMode,
            upscalesFullHDVideo: viewModel.comfort.upscalesFullHDVideo,
            videoFormat: qos.videoFormat,
            sourceVideoWidth: qos.sourceVideoWidth,
            sourceVideoHeight: qos.sourceVideoHeight
        )
    }

    static func audioSummary(
        speakerLayoutOverride: SpeakerLayoutOverrideMode,
        sessionRoomAutoLayout: String,
        audioFormatBadge: String,
        audioDecoderLabel: String,
        audioEnhancement: AudioEnhancementMode,
        audioDelayMs: Int,
        binauralStatus: AudioBinauralStatus
    ) -> String {
        let delayDisplay = audioDelayMs == 0 ? nil : ComfortPreferences.displayAudioDelayMs(audioDelayMs)
        return AudioChainSummaryFormatter.summary(
            speakerLayoutOverride: speakerLayoutOverride,
            sessionRoomAutoLayout: sessionRoomAutoLayout,
            audioFormatBadge: audioFormatBadge,
            audioDecoderLabel: audioDecoderLabel,
            audioEnhancement: audioEnhancement,
            audioDelayDisplay: delayDisplay,
            binauralStatus: binauralStatus
        )
    }

    private var audioSummary: String {
        let qos = viewModel.qosReporter
        let track = viewModel.trackController
        return Self.audioSummary(
            speakerLayoutOverride: viewModel.comfort.speakerLayoutOverride,
            sessionRoomAutoLayout: qos.sessionRoomAutoLayout,
            audioFormatBadge: qos.audioFormatBadge,
            audioDecoderLabel: qos.activeAudioDecoder ?? qos.audioDelivery.rawValue,
            audioEnhancement: track.audioEnhancement,
            audioDelayMs: track.audioDelayMs,
            binauralStatus: track.binauralStatus
        )
    }

    private var bitrateSummary: String {
        let inst = telemetry?.instantBitrateMbps.map { "\(LunaCopy.formatDecimal($0)) Mbps" } ?? "-"
        let avg = telemetry?.averageBitrateMbps.map { "snitt \(LunaCopy.formatDecimal($0)) Mbps" } ?? ""
        return avg.isEmpty ? inst : "\(inst) (\(avg))"
    }

    private var bufferAndNetworkSummary: String {
        let link = telemetry?.networkThroughputMbps.map { String(format: "%.0f Mbps", $0) } ?? "idle"
        let fwdSeconds: Double = {
            if let f = telemetry?.forwardBufferSeconds {
                return f
            }
            return max(0, engine.bufferedPosition - engine.currentTime)
        }()
        let winMiB: String = {
            if let ahead = telemetry?.readerWindowAheadBytes, ahead > 0 {
                return " · +\(LunaCopy.formatDecimal(Double(ahead) / 1_048_576.0)) MiB vindu"
            }
            if cacheStatus.currentForwardBytes > 0 {
                return " · +\(LunaCopy.formatDecimal(Double(cacheStatus.currentForwardBytes) / 1_048_576.0)) MiB \(LunaCopy.quickBufferTitle)"
            }
            return ""
        }()
        return "\(link) · \(LunaCopy.formatDecimal(fwdSeconds))s buffer\(winMiB)"
    }

    private var editionAndMemorySummary: String {
        let session = viewModel.sessionController.activeSession
        let vfs = viewModel.qosReporter.lastVfsTelemetry
        let rawSource = (session?.selectedCandidate.source ?? vfs?.streamSource ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let tier: String
        if rawSource.contains("easynews") {
            tier = "Easynews HTTPS"
        } else {
            tier = session?.selectedCandidate.sourceBadgeLabel
                ?? vfs?.streamSource
                ?? "Direkte"
        }
        let zeroCopy = session?.stream.zeroCopyMode ?? "206"
        let rss = telemetry.map { "\($0.rssMb) MB RAM" } ?? "-"
        let base = "\(tier) (\(zeroCopy)) · \(rss)"
        if let ramBuf = Self.formatSessionCacheLabel(cacheStatus) {
            return "\(base) · \(ramBuf)"
        }
        return base
    }

    private func hudRow(_ key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(LunaTheme.Font.badge.monospaced())
                .foregroundStyle(LunaTheme.muted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: Self.keyColumnWidth, alignment: .leading)
            Text(value)
                .font(LunaTheme.Font.badge.monospacedDigit())
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}
