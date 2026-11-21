import Foundation
import MediaPlayer
import UIKit
import AetherBridge

/// Top-level `nonisolated` factory so `MPMediaItemArtwork`'s Objective-C `requestHandler`
/// never inherits dynamic `@MainActor` isolation under Swift 6 (`SE-0423`) when `MediaPlayer`
/// requests artwork bitmaps on background `MediaRemote` queues.
enum NowPlayingArtworkFactory {
    static func makeArtwork(cgImage: CGImage) -> MPMediaItemArtwork {
        let size = CGSize(width: max(1, cgImage.width), height: max(1, cgImage.height))
        return MPMediaItemArtwork(boundsSize: size) { @Sendable _ in
            UIImage(cgImage: cgImage)
        }
    }
}

/// Publishes tvOS Control Center / iPhone Remote Now Playing metadata, chapter/next-episode
/// command handlers, and decoded poster/backdrop artwork via `AetherEngine 7.71.0`.
@MainActor
enum PlayerNowPlayingCoordinator {
    static func publish(
        session: TvPlaybackSession,
        client: LunaCoreClient,
        viewModel: PlayerViewModel
    ) {
        viewModel.nowPlayingArtworkTask?.cancel()
        viewModel.nowPlayingArtworkTask = nil

        let engine = viewModel.engine
        let baseInfo = makeBaseInfo(for: session)
        engine.setVideoNowPlayingInfo(baseInfo)

        if session.nextEpisode != nil {
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
                maxPixelSize: 640,
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

    static func makeBaseInfo(for session: TvPlaybackSession) -> [String: Any] {
        let meta = EpisodeTitleFormatter.nowPlayingMetadata(for: session.item)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: meta.title
        ]

        if let artist = meta.artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let albumTitle = meta.albumTitle, !albumTitle.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }

        return info
    }
}
