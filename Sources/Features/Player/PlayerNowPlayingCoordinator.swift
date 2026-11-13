import Foundation
import MediaPlayer
import UIKit
import AetherBridge

private struct SendableCGImageBox: @unchecked Sendable {
    let cgImage: CGImage
}

/// Top-level `nonisolated` factory so `MPMediaItemArtwork`'s Objective-C `requestHandler`
/// never inherits dynamic `@MainActor` isolation under Swift 6 (`SE-0423`) when `MediaPlayer`
/// requests artwork bitmaps on background `MediaRemote` queues.
enum NowPlayingArtworkFactory {
    static func makeArtwork(cgImage: CGImage) -> MPMediaItemArtwork {
        let size = CGSize(width: max(1, cgImage.width), height: max(1, cgImage.height))
        let box = SendableCGImageBox(cgImage: cgImage)
        return MPMediaItemArtwork(boundsSize: size) { @Sendable _ in
            UIImage(cgImage: box.cgImage)
        }
    }
}

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

            let artwork = NowPlayingArtworkFactory.makeArtwork(cgImage: cgImage)
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
            MPMediaItemPropertyTitle: session.item.title
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

        return info
    }
}
