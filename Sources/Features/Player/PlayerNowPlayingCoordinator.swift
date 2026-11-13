import Foundation
import MediaPlayer
import UIKit
import AetherBridge

/// Publishes tvOS Control Center / iPhone Remote Now Playing metadata, chapter/next-episode
/// command handlers, and decoded poster/backdrop artwork via `AetherEngine 7.65.0`.
@MainActor
enum PlayerNowPlayingCoordinator {
    static func publish(
        session: TvPlaybackSession,
        client: MediaOSClient,
        viewModel: PlayerViewModel
    ) {
        viewModel.nowPlayingArtworkTask?.cancel()
        viewModel.nowPlayingArtworkTask = nil

        let engine = viewModel.engine
        let baseInfo = makeBaseInfo(for: session)
        engine.setVideoNowPlayingInfo(baseInfo)

        if let next = session.nextEpisode {
            engine.setNowPlayingTrackCommands(
                next: { [weak viewModel] in
                    guard let vm = viewModel,
                          let currentNext = vm.activeSession?.nextEpisode else {
                        return
                    }
                    vm.playNextEpisode(currentNext)
                },
                previous: nil
            )
            _ = next
        } else {
            engine.setNowPlayingTrackCommands(next: nil, previous: nil)
        }

        guard let artURL = client.resolveArtworkURL(session.item.posterUrl ?? session.item.backdropUrl) else {
            return
        }

        let targetSessionID = session.sessionId
        viewModel.nowPlayingArtworkTask = Task { @MainActor [weak viewModel] in
            guard let cgImage = await ArtworkPipeline.shared.loadImage(
                url: artURL,
                maxPixelSize: 600,
                client: client
            ) else {
                return
            }
            guard !Task.isCancelled,
                  let viewModel,
                  viewModel.activeSession?.sessionId == targetSessionID else {
                return
            }

            let boundsSize = CGSize(width: cgImage.width, height: cgImage.height)
            let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { _ in
                UIImage(cgImage: cgImage)
            }
            var enrichedInfo = makeBaseInfo(for: session)
            enrichedInfo[MPMediaItemPropertyArtwork] = artwork
            viewModel.engine.setVideoNowPlayingInfo(enrichedInfo)
        }
    }

    static func clear(engine: AetherEngine) {
        engine.setNowPlayingTrackCommands(next: nil, previous: nil)
        engine.setVideoNowPlayingInfo([:])
    }

    private static func makeBaseInfo(for session: TvPlaybackSession) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: session.item.title,
            MPMediaItemPropertyMediaType: session.item.mediaType == "movie"
                ? MPMediaType.movie.rawValue
                : MPMediaType.tvShow.rawValue
        ]

        if let seriesTitle = session.item.seriesTitle, !seriesTitle.isEmpty {
            info[MPMediaItemPropertyArtist] = seriesTitle
            if let s = session.item.season, let e = session.item.episode {
                info[MPMediaItemPropertyAlbumTitle] = String(format: "%@ · S%02dE%02d", seriesTitle, s, e)
            } else {
                info[MPMediaItemPropertyAlbumTitle] = seriesTitle
            }
        } else if let year = session.item.year {
            info[MPMediaItemPropertyArtist] = String(year)
        }

        let declaredDuration = session.stream.declaredDurationSeconds ?? session.item.runtimeSeconds ?? 0
        if declaredDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = declaredDuration
        }

        return info
    }
}
