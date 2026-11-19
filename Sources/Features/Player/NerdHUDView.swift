import SwiftUI
import AetherBridge

/// Isolated 1 Hz diagnostic HUD observing `engine.diagnostics.$liveTelemetry`
/// in a leaf view so telemetry ticks never re-render the video player shell.
struct NerdHUDView: View {
    let engine: AetherEngine
    @ObservedObject var viewModel: PlayerViewModel

    @State private var telemetry: LiveTelemetry?
    @State private var cacheStatus: SessionCacheStatus = .inactive

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LunaTheme.emerald)
                    .frame(width: 8, height: 8)
                Text("Teknisk oversikt · \(viewModel.activeSession?.roomName ?? "TV")")
                    .font(LunaTheme.Font.badge)
                    .foregroundStyle(LunaTheme.linen)
            }

            hudRow("Video", value: videoSummary)
            hudRow("HDR / Rute", value: "\(viewModel.videoFormatBadge) · \(viewModel.videoRoute.rawValue)")
            hudRow("Dekoder", value: decoderSummary)
            hudRow("Lydkjede", value: audioSummary)
            if let obj = telemetry?.objectAudio {
                hudRow("Objektlyd", value: "\(obj.layout.rawValue) · \(obj.activeObjects)/\(obj.objects) obj (\(obj.elevatedObjects) høyde)")
            }
            hudRow("Bitrate", value: bitrateSummary)
            hudRow("HTTP 206 / Buffer", value: bufferAndNetworkSummary)
            hudRow("Kilde / Minne", value: sourceAndMemorySummary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 580, alignment: .leading)
        .background(LunaTheme.cinemaGlass, in: RoundedRectangle(cornerRadius: LunaTokens.Radius.poster, style: .continuous))
        .lunaTopLightEdge(cornerRadius: LunaTokens.Radius.poster)
        .allowsHitTesting(false)
        .onReceive(engine.diagnostics.$liveTelemetry) { telemetry = $0 }
        .onReceive(engine.diagnostics.$sessionCacheStatus) { cacheStatus = $0 }
    }

    private var videoSummary: String {
        let codec = (viewModel.sourceVideoCodecName ?? "hevc").uppercased()
        let w = viewModel.sourceVideoWidth
        let h = viewModel.sourceVideoHeight
        let res = (w > 0 && h > 0) ? "\(w)×\(h)" : "Auto"
        let fpsVal = telemetry?.observedFps ?? viewModel.sourceVideoFrameRate
        let fps = fpsVal.map {
            String(format: "%.3g fps", locale: Locale(identifier: "en_US_POSIX"), $0).replacingOccurrences(of: ".", with: ",")
        } ?? "-"
        return "\(codec) · \(res) @ \(fps)"
    }

    private var decoderSummary: String {
        let vDec = viewModel.activeVideoDecoder ?? (viewModel.videoRoute == .software ? "FFmpeg SW" : "VideoToolbox HW")
        let dropped = telemetry?.droppedFrameCount ?? 0
        return "\(vDec) · \(dropped) mistet"
    }

    private var audioSummary: String {
        let aDec = viewModel.activeAudioDecoder ?? viewModel.audioDelivery.rawValue
        let delaySuffix = viewModel.audioDelayMs == 0 ? "" : " · \(ComfortPreferences.formatAudioDelayMs(viewModel.audioDelayMs))"
        return "\(viewModel.audioFormatBadge) (\(aDec))\(delaySuffix)"
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
                return " · +\(LunaCopy.formatDecimal(Double(ahead) / 1_048_576.0)) MiB lesevindu"
            }
            if cacheStatus.currentForwardBytes > 0 {
                return " · +\(LunaCopy.formatDecimal(Double(cacheStatus.currentForwardBytes) / 1_048_576.0)) MiB cache"
            }
            return ""
        }()
        return "\(link) · \(LunaCopy.formatDecimal(fwdSeconds))s buffer\(winMiB)"
    }

    private var sourceAndMemorySummary: String {
        let tier = viewModel.activeSession?.selectedCandidate.sourceBadgeLabel
            ?? viewModel.lastVfsTelemetry?.streamSource
            ?? "Direkte"
        let zeroCopy = viewModel.activeSession?.stream.zeroCopyMode ?? "206"
        let rss = telemetry.map { "\($0.rssMb) MB RAM" } ?? "-"
        return "\(tier) (\(zeroCopy)) · \(rss)"
    }

    private func hudRow(_ key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(LunaTheme.Font.badge.monospaced())
                .foregroundStyle(LunaTheme.muted)
                .frame(width: 152, alignment: .leading)
            Text(value)
                .font(LunaTheme.Font.badge.monospacedDigit())
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
