import SwiftUI
import AetherBridge

enum PlayerSheetModal: String, Identifiable {
    case audio
    case subtitles
    case sources
    case diagnostics

    var id: String { rawValue }
}

/// Leaf time scrubber observing `engine.clock.$currentTime` so 10 Hz clock updates
/// stay confined to this progress bar.
struct PlayerScrubberBarView: View {
    let engine: AetherEngine
    let duration: Double

    @State private var currentTime: Double = 0
    @State private var bufferedTime: Double = 0

    var body: some View {
        let effectiveDuration = max(duration, currentTime, 1)
        let progressRatio = min(1.0, max(0.0, currentTime / effectiveDuration))
        let bufferRatio = min(1.0, max(0.0, bufferedTime / effectiveDuration))

        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white.opacity(0.34))
                        .frame(width: geo.size.width * CGFloat(bufferRatio))
                    Capsule()
                        .fill(Color(red: 0.96, green: 0.77, blue: 0.42))
                        .frame(width: geo.size.width * CGFloat(progressRatio))
                }
            }
            .frame(height: 10)

            HStack {
                Text(Self.formatSeconds(currentTime))
                Spacer()
                Text("-\(Self.formatSeconds(max(0, effectiveDuration - currentTime)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .onReceive(engine.clock.$currentTime) { currentTime = $0 }
        .onReceive(engine.clock.$bufferedPosition) { bufferedTime = $0 }
    }

    static func formatSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

struct AudioTrackSheetView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Lydspor")
                .font(.title2.bold())

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(viewModel.audioTracks) { track in
                        let isSelected = viewModel.activeAudioTrackIndex == track.id
                        Button {
                            viewModel.engine.selectAudioTrack(index: track.id)
                            onClose()
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "speaker.wave.2")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trackTitle(track))
                                        .font(.headline)
                                    Text(trackSubtitle(track))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .padding(56)
    }

    private func trackTitle(_ track: TrackInfo) -> String {
        if !track.name.isEmpty {
            return track.name
        }
        return (track.language ?? "Lydspor \(track.id)").uppercased()
    }

    private func trackSubtitle(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if let lang = track.language {
            parts.append(lang.uppercased())
        }
        if let profile = track.profile, !profile.isEmpty {
            parts.append(profile)
        } else {
            parts.append(track.codec.uppercased())
        }
        if track.isAtmos {
            parts.append("Dolby Atmos")
        } else if track.isDTSX {
            parts.append("DTS:X")
        } else if let layout = track.channelLayout {
            parts.append(layout)
        }
        return parts.joined(separator: " · ")
    }
}

struct SubtitleTrackSheetView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Undertekster")
                .font(.title2.bold())

            HStack(spacing: 18) {
                Text(String(format: "Synkronisering: %+.1f s", viewModel.subtitleDelaySeconds))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button("-0.2s") {
                    viewModel.adjustSubtitleDelay(by: -0.2)
                }
                Button("+0.2s") {
                    viewModel.adjustSubtitleDelay(by: 0.2)
                }
            }

            ScrollView {
                VStack(spacing: 14) {
                    Button {
                        viewModel.engine.clearSubtitle()
                        onClose()
                    } label: {
                        HStack {
                            Image(systemName: viewModel.activeSubtitleTrackIndex == nil ? "checkmark.circle.fill" : "circle")
                            Text("Av")
                                .font(.headline)
                            Spacer()
                        }
                    }

                    ForEach(viewModel.subtitleTracks) { track in
                        let isSelected = viewModel.activeSubtitleTrackIndex == track.id
                        Button {
                            viewModel.engine.selectSubtitleTrack(index: track.id)
                            onClose()
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "captions.bubble")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.name.isEmpty ? (track.language?.uppercased() ?? "Undertekst") : track.name)
                                        .font(.headline)
                                    Text([
                                        track.language?.uppercased(),
                                        track.codec.uppercased(),
                                        track.isExternal ? "NVMe .srt" : nil,
                                        track.isForced ? "Forced" : nil,
                                    ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .padding(56)
    }
}

struct SourceSwitcherSheetView: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Bytt kilde (beholder tidskode)")
                .font(.title2.bold())

            if viewModel.isLoadingAlternatives {
                ProgressView("Henter rangerte kilder…")
            } else if viewModel.alternatives.isEmpty {
                Text("Ingen alternative kilder funnet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(viewModel.alternatives) { cand in
                            let isCurrent = cand.isActive == true || cand.candidateId == viewModel.activeSession?.selectedCandidate.candidateId
                            Button {
                                guard !isCurrent else {
                                    onClose()
                                    return
                                }
                                onClose()
                                Task {
                                    await viewModel.switchSource(to: cand.candidateId)
                                }
                            } label: {
                                HStack(spacing: 18) {
                                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(cand.displayHeadline)
                                            .font(.headline)
                                        Text(cand.releaseTitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if let size = cand.formattedSize {
                                        Text(size)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
        .padding(56)
        .task {
            await viewModel.loadAlternatives()
        }
    }
}

struct DiagnosticsSheetView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Teknisk strømstatus")
                .font(.title2.bold())

            diagRow("Rom / Profil", value: "\(viewModel.activeSession?.roomName ?? "-") (\(viewModel.activeSession?.hardwareProfile ?? "-"))")
            diagRow("Kilde", value: viewModel.activeSession?.selectedCandidate.displayHeadline ?? "-")
            diagRow("Zero-Copy modus", value: viewModel.activeSession?.stream.zeroCopyMode ?? "-")
            diagRow("Skjermformat (aktivt)", value: formatVideoFormat(viewModel.videoFormat))
            diagRow("Dolby Vision-profil (kilde)", value: viewModel.sourceDVProfile.map { "Profile \($0)" } ?? "Ingen")
            diagRow("Videorute", value: viewModel.videoRoute.rawValue)
            diagRow("Lydlevering", value: viewModel.audioDelivery.rawValue)
            diagRow("VFS-lås & puls", value: "Aktiv (15s intervall · 4t pauselås)")
        }
        .padding(56)
    }

    private func formatVideoFormat(_ fmt: VideoFormat) -> String {
        switch fmt {
        case .dolbyVision: return "Dolby Vision"
        case .hdr10Plus: return "HDR10+"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .sdr: return "SDR"
        }
    }

    private func diagRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
        }
    }
}
