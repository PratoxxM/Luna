import Foundation

@MainActor
extension MediaDetailViewModel {
    // MARK: - Playback, Source Picker & Delete Intents

    func launchPrimaryPlayback() {
        guard let detail else { return }
        ItemDetailMemoryCache.invalidate(itemId: itemId, tmdbId: detail.ids.tmdb)
        let target = primaryTargetInfo(detail)
        let handoff = preResolve.consumeHandoffForPlayback(
            itemId: target.itemId,
            startPosition: target.startPos,
            client: refreshedClient()
        )
        sessionContext?.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            season: target.season,
            episode: target.episode,
            startPositionSeconds: target.startPos,
            prepareToken: handoff.prepareToken,
            preparedSession: handoff.preparedSession,
            inflightPrepareTask: handoff.inflightPrepareTask,
            inflightPrepareToken: handoff.inflightPrepareToken,
            preparedStreamSecretRegistered: handoff.preparedStreamSecretRegistered,
            backdropUrl: detail.backdropUrl ?? detail.cardBackdropUrl,
            logoUrl: detail.logoUrl
        )
    }

    func playEpisode(_ ep: TvEpisodeCard) {
        guard let detail, ep.isUpcoming != true else { return }
        ItemDetailMemoryCache.invalidate(itemId: itemId, tmdbId: detail.ids.tmdb)
        let handoff = preResolve.consumeHandoffForPlayback(
            itemId: ep.itemId,
            startPosition: ep.progress?.positionSeconds,
            client: refreshedClient()
        )
        let cleanEpisodeTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
            ep.title,
            seriesTitle: detail.title,
            season: ep.seasonNumber,
            episode: ep.episodeNumber,
            episodeCode: ep.seasonEpisodeCode
        ) ?? ""
        sessionContext?.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: ep.itemId,
            title: cleanEpisodeTitle,
            seriesTitle: detail.title,
            season: ep.seasonNumber,
            episode: ep.episodeNumber,
            startPositionSeconds: ep.progress?.positionSeconds,
            prepareToken: handoff.prepareToken,
            preparedSession: handoff.preparedSession,
            inflightPrepareTask: handoff.inflightPrepareTask,
            inflightPrepareToken: handoff.inflightPrepareToken,
            preparedStreamSecretRegistered: handoff.preparedStreamSecretRegistered,
            backdropUrl: ep.stillUrl ?? detail.backdropUrl,
            logoUrl: detail.logoUrl
        )
    }

    func openPrimarySourcePicker() {
        guard let detail else { return }
        let target = primaryTargetInfo(detail)
        sourcePickerContext = SourcePickerContext(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            season: target.season,
            episode: target.episode,
            startPositionSeconds: target.startPos,
            existingPrepareToken: preResolve.matchingToken(
                for: target.itemId,
                startPosition: target.startPos
            ),
            backdropUrl: detail.backdropUrl ?? detail.cardBackdropUrl,
            logoUrl: detail.logoUrl
        )
    }

    func openEpisodeSourcePicker(_ ep: TvEpisodeCard) {
        guard let detail, ep.isUpcoming != true else { return }
        let cleanEpisodeTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
            ep.title,
            seriesTitle: detail.title,
            season: ep.seasonNumber,
            episode: ep.episodeNumber,
            episodeCode: ep.seasonEpisodeCode
        ) ?? ""
        sourcePickerContext = SourcePickerContext(
            itemId: ep.itemId,
            title: cleanEpisodeTitle,
            seriesTitle: detail.title,
            season: ep.seasonNumber,
            episode: ep.episodeNumber,
            startPositionSeconds: ep.progress?.positionSeconds,
            existingPrepareToken: preResolve.matchingToken(
                for: ep.itemId,
                startPosition: ep.progress?.positionSeconds
            ),
            backdropUrl: ep.stillUrl ?? detail.backdropUrl,
            logoUrl: detail.logoUrl
        )
    }

    func launchSelectedSource(
        _ picked: TvCandidateInfo,
        reusedToken: String?,
        createdPreparedSession: TvPlaybackSession? = nil,
        context target: SourcePickerContext
    ) {
        ItemDetailMemoryCache.invalidate(itemId: itemId, tmdbId: detail?.ids.tmdb)
        let currentClient = refreshedClient()
        var effectiveToken: String? = reusedToken
        var effectiveCandidateId: String? = reusedToken == nil ? picked.candidateId : nil
        var handedOverSession: TvPlaybackSession? = nil
        var handedOverInflight: Task<TvPrepareResponse?, Never>? = nil
        var handedOverInflightToken: String? = nil
        var handedOverSecretRegistered = false

        if reusedToken == SourcePickerTokenPolicy.adoptInflightDefaultSentinel {
            let handoff = preResolve.consumeHandoffForPlayback(
                itemId: target.itemId,
                startPosition: target.startPositionSeconds,
                client: currentClient
            )
            if let readySession = handoff.preparedSession,
               readySession.selectedCandidate.candidateId == picked.candidateId {
                effectiveToken = handoff.prepareToken ?? readySession.sessionId
                effectiveCandidateId = nil
                handedOverSession = readySession
                handedOverSecretRegistered = handoff.preparedStreamSecretRegistered
            } else if handoff.inflightPrepareTask != nil {
                effectiveToken = nil
                effectiveCandidateId = nil
                handedOverInflight = handoff.inflightPrepareTask
                handedOverInflightToken = handoff.inflightPrepareToken
            } else {
                if let mismatchedSid = handoff.preparedSession?.sessionId ?? handoff.prepareToken,
                   !mismatchedSid.isEmpty,
                   let currentClient {
                    DetailPreResolveController.stopSessionDetached(sessionId: mismatchedSid, client: currentClient)
                }
                effectiveToken = nil
                effectiveCandidateId = picked.candidateId
            }
        } else if let reusedToken {
            if let createdPreparedSession {
                preResolve.discardPreparedSession(
                    excludingSessionId: createdPreparedSession.sessionId,
                    client: currentClient
                )
                handedOverSession = createdPreparedSession
            } else {
                let handoff = preResolve.consumeHandoffForPlayback(
                    itemId: target.itemId,
                    startPosition: target.startPositionSeconds,
                    client: currentClient
                )
                if handoff.preparedSession == nil {
                    preResolve.discardPreparedSession(
                        excludingSessionId: reusedToken,
                        client: currentClient
                    )
                }
                handedOverSession = handoff.preparedSession
                handedOverInflight = handoff.inflightPrepareTask
                handedOverInflightToken = handoff.inflightPrepareToken
                handedOverSecretRegistered = handoff.preparedStreamSecretRegistered
            }
        } else {
            preResolve.discardPreparedSession(client: currentClient)
        }
        sourcePickerContext = nil
        sessionContext?.activePlaybackTarget = PlaybackLaunchRequest(
            itemId: target.itemId,
            title: target.title,
            seriesTitle: target.seriesTitle,
            season: target.season,
            episode: target.episode,
            startPositionSeconds: target.startPositionSeconds,
            candidateId: effectiveCandidateId,
            prepareToken: effectiveToken,
            preparedSession: handedOverSession,
            inflightPrepareTask: handedOverInflight,
            inflightPrepareToken: handedOverInflightToken,
            preparedStreamSecretRegistered: handedOverSecretRegistered,
            backdropUrl: target.backdropUrl ?? detail?.backdropUrl,
            logoUrl: target.logoUrl ?? detail?.logoUrl
        )
    }

    func prepareForDeletePreflight() {
        preResolve.discardPreparedSession(client: refreshedClient())
    }

    func requestDeleteTitle() {
        guard let detail else { return }
        pendingDeleteTarget = TvDeleteRequestTarget(
            kind: detail.mediaType,
            itemId: detail.itemId,
            tmdbId: detail.ids.tmdb,
            tvdbId: detail.ids.tvdb,
            title: detail.title,
            subtitle: detail.year.map(String.init),
            scope: detail.mediaType == "series" ? .series : .title
        )
    }

    func requestDeleteSeason(_ seasonNum: Int) {
        guard let detail else { return }
        pendingDeleteTarget = TvDeleteRequestTarget(
            kind: "series",
            itemId: detail.itemId,
            tmdbId: detail.ids.tmdb,
            tvdbId: detail.ids.tvdb,
            title: detail.title,
            subtitle: "Sesong \(seasonNum)",
            scope: .season,
            season: seasonNum
        )
    }

    func requestDeleteEpisode(_ ep: TvEpisodeCard) {
        guard let detail else { return }
        pendingDeleteTarget = TvDeleteRequestTarget(
            kind: "series",
            itemId: ep.itemId,
            tmdbId: detail.ids.tmdb,
            tvdbId: detail.ids.tvdb,
            title: detail.title,
            subtitle: "\(ep.seasonEpisodeCode) · \(ep.nonGenericTitle ?? ep.title)",
            scope: .episode,
            season: ep.seasonNumber,
            episode: ep.episodeNumber
        )
    }

    func handleDeleted(target: TvDeleteRequestTarget) async -> Bool {
        pendingDeleteTarget = nil
        ItemDetailMemoryCache.invalidate(itemId: target.itemId, tmdbId: target.tmdbId ?? detail?.ids.tmdb)
        if target.isWholeTitle {
            detailLoadTask?.cancel()
            detailLoadTask = nil
            if let sessionContext {
                lastSeenRefreshNonce = sessionContext.homeRefreshNonce &+ 1
                sessionContext.notifyContentMutated()
            }
            return true
        }
        await markLocalMutationAndReload()
        return false
    }

    // MARK: - Formatting Helpers

    func heroPrimaryPlayTitle(_ item: TvItemDetail) -> String {
        let base = primaryPlayLabel(item)
        if base.hasPrefix("Fortsett") {
            let targetProg: TvWatchProgress? = {
                if item.mediaType == "series", let next = item.nextUp,
                   let ep = episodes.first(where: { $0.seasonNumber == next.season && $0.episodeNumber == next.episode }),
                   let epProg = ep.progress, epProg.durationSeconds > epProg.positionSeconds {
                    return epProg
                }
                return item.progress
            }()
            guard let prog = targetProg,
                  prog.positionSeconds.isFinite,
                  prog.durationSeconds.isFinite,
                  prog.positionSeconds > 30,
                  prog.durationSeconds > prog.positionSeconds,
                  let rawMins = Int(exactly: ((prog.durationSeconds - prog.positionSeconds) / 60.0).rounded()) else {
                return base
            }
            let totalMins = max(1, rawMins)
            let remText = totalMins >= 60 && totalMins % 60 > 0
                ? "\(totalMins / 60) t \(totalMins % 60) min igjen"
                : (totalMins >= 60 ? "\(totalMins / 60) t igjen" : "\(totalMins) min igjen")
            return "\(base) · \(remText)"
        }

        if item.mediaType == "series" {
            let targetSeason = item.nextUp?.season ?? selectedSeasonNumber
            let targetEpisode = item.nextUp?.episode ?? 1
            if let ep = episodes.first(where: { $0.seasonNumber == targetSeason && $0.episodeNumber == targetEpisode }),
               let epRuntime = ep.formattedRuntime, !epRuntime.isEmpty {
                return "\(base) · \(epRuntime)"
            }
        }
        if let runtime = item.formattedRuntime, !runtime.isEmpty {
            return "\(base) · \(runtime)"
        }
        return base
    }

    func primaryPlayLabel(_ item: TvItemDetail) -> String {
        let inProgress = (item.progress?.positionSeconds ?? 0) > 30 && (item.progress?.percent ?? 0) < 90
        if item.mediaType == "series" {
            if let next = item.nextUp {
                if inProgress,
                   item.progress?.season == next.season,
                   item.progress?.episode == next.episode {
                    return "Fortsett S\(next.season) E\(next.episode)"
                }
                return "Spill S\(next.season) E\(next.episode)"
            }
            return item.watched ? "Spill på nytt S1 E1" : "Spill S1 E1"
        }
        if inProgress {
            return "Fortsett"
        }
        return "Spill av"
    }

    func primaryTargetInfo(_ item: TvItemDetail) -> (
        itemId: String,
        title: String,
        seriesTitle: String?,
        season: Int?,
        episode: Int?,
        startPos: Double?
    ) {
        let itemProgPos: Double? = (item.progress?.percent ?? 0) < 90 ? item.progress?.positionSeconds : 0
        if item.mediaType == "series" {
            let rewatchFromStart = item.nextUp == nil && item.watched
            let s = rewatchFromStart ? 1 : (item.nextUp?.season ?? selectedSeasonNumber)
            let playable = episodes.filter { $0.isUpcoming != true }
            let e = rewatchFromStart ? 1 : (item.nextUp?.episode ?? playable.first?.episodeNumber ?? 1)
            let epId: String
            if let tmdb = item.ids.tmdb {
                epId = "episode:tmdb:\(tmdb):s\(s):e\(e)"
            } else {
                epId = item.itemId
            }
            let matchingEp = episodes.first { $0.seasonNumber == s && $0.episodeNumber == e }
            let startPos: Double?
            if rewatchFromStart {
                startPos = 0
            } else if let epProg = matchingEp?.progress {
                startPos = epProg.percent < 90 ? epProg.positionSeconds : 0
            } else if let itemProg = item.progress,
                      itemProg.season == s,
                      itemProg.episode == e,
                      itemProg.percent < 90 {
                startPos = itemProg.positionSeconds
            } else {
                startPos = 0
            }
            let cleanEpisodeTitle = EpisodeTitleFormatter.nonGenericEpisodeTitle(
                matchingEp?.title,
                seriesTitle: item.title,
                season: s,
                episode: e,
                episodeCode: matchingEp?.seasonEpisodeCode
            )
            return (epId, cleanEpisodeTitle ?? "", item.title, s, e, startPos)
        }
        return (item.itemId, item.title, nil, nil, nil, itemProgPos)
    }
}
