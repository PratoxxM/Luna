import Foundation
import AetherBridge

extension PlayerViewModel {
    // MARK: - Audio & Subtitle Controls

    func selectAudioTrack(_ index: Int) {
        activeAudioTrackIndex = index
        guard previewAudioOptions.isEmpty else { return }
        engine.selectAudioTrack(index: index)
        if comfort.smartNordicSubtitleRule && !userManuallySelectedSubtitle {
            smartRuleTask?.cancel()
            smartRuleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                self?.applySmartSubtitleRule()
            }
        }
    }

    func adjustAudioDelay(byMs deltaMs: Int) {
        applyAudioDelayMs(audioDelayMs + deltaMs, debounceEngineCommit: true)
    }

    func resetAudioDelay() {
        applyAudioDelayMs(0, debounceEngineCommit: false)
    }

    private func applyAudioDelayMs(_ targetMs: Int, debounceEngineCommit: Bool) {
        let clamped = ComfortPreferences.clampAudioDelayMs(targetMs)
        audioDelayMs = clamped
        comfort.audioDelayMs = clamped
        audioDelayCommitTask?.cancel()
        audioDelayCommitTask = nil

        guard !isResolving && !isSwitchingSource else {
            return
        }

        let targetSeconds = Double(clamped) / 1000.0
        if !debounceEngineCommit {
            engine.setAudioDelay(targetSeconds)
            return
        }

        audioDelayCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, !self.isResolving, !self.isSwitchingSource else { return }
            self.engine.setAudioDelay(Double(self.audioDelayMs) / 1000.0)
            self.audioDelayCommitTask = nil
        }
    }

    func setAudioEnhancement(_ mode: AudioEnhancementMode) {
        audioEnhancement = mode
        engine.setAudioShaping(comfort.buildAudioShaping(enhancement: mode))
    }

    func selectSubtitleManually(_ index: Int) {
        userManuallySelectedSubtitle = true
        activeSubtitleTrackIndex = index
        guard previewSubtitleOptions.isEmpty else { return }
        engine.selectSubtitleTrack(index: index)
    }

    func clearSubtitleManually() {
        userManuallySelectedSubtitle = true
        activeSubtitleTrackIndex = nil
        guard previewSubtitleOptions.isEmpty else { return }
        engine.clearSubtitle()
    }

    func adjustSubtitleDelay(by delta: Double) {
        let rounded = ((subtitleDelaySeconds + delta) * 10).rounded() / 10
        let updated = min(max(rounded, -10.0), 10.0)
        engine.setSoftwareSubtitleDelay(updated)
        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
    }

    func resetSubtitleDelay() {
        engine.setSoftwareSubtitleDelay(0)
        subtitleDelaySeconds = engine.softwareSubtitleDelaySeconds
    }

    func applySmartSubtitleRule() {
        guard comfort.smartNordicSubtitleRule, !userManuallySelectedSubtitle else { return }
        let liveAudioTracks = engine.audioTracks
        let liveAudioIdx = engine.activeAudioTrackIndex
        let liveSubtitleTracks = engine.subtitleTracks
        let liveSubIdx = engine.activeSubtitleTrackIndex

        audioTracks = liveAudioTracks
        activeAudioTrackIndex = liveAudioIdx
        subtitleTracks = liveSubtitleTracks
        activeSubtitleTrackIndex = liveSubIdx

        let activeAudio = liveAudioTracks.first(where: { $0.id == liveAudioIdx }) ?? liveAudioTracks.first
        let decision = SmartTrackRuleEngine.evaluate(activeAudio: activeAudio, subtitleTracks: liveSubtitleTracks)
        switch decision {
        case .clearSubtitles:
            if liveSubIdx != nil {
                engine.clearSubtitle()
                activeSubtitleTrackIndex = nil
            }
        case .selectTrack(let trackID):
            if liveSubIdx != trackID {
                engine.selectSubtitleTrack(index: trackID)
                activeSubtitleTrackIndex = trackID
            }
        case .keepCurrent:
            break
        }
    }
}
