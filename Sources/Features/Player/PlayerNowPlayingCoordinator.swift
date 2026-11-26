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

/// Publishes tvOS Control Center / iPhone Remote Now Playing metadata
/// and decoded poster/backdrop artwork via `AetherEngine 7.76.0`.
@MainActor
enum PlayerNowPlayingCoordinator {
    static let nowPlayingArtworkMaxPixels = 900

    static func publish(
        session: TvPlaybackSession,
        client: LunaCoreClient,
        viewModel: PlayerViewModel
    ) {
        viewModel.sessionController.nowPlayingArtworkTask?.cancel()
        viewModel.sessionController.nowPlayingArtworkTask = nil

        let engine = viewModel.engine
        var baseInfo = makeBaseInfo(for: session)
        let resolvedArtURL = client.resolveArtworkURL(
            session.item.posterUrl ?? session.item.backdropUrl,
            target: .poster2x
        )
        let cachedCGImage = resolvedArtURL.flatMap { artURL in
            ArtworkPipeline.shared.anyMemoryCachedImage(
                for: artURL,
                preferredMaxPixelSize: nowPlayingArtworkMaxPixels
            )?.image
        }
        if let cachedCGImage {
            baseInfo[MPMediaItemPropertyArtwork] = NowPlayingArtworkFactory.makeArtwork(cgImage: cachedCGImage)
        }
        engine.setVideoNowPlayingInfo(baseInfo)

        // Keep track commands cleared so AetherEngine's NowPlayingArbiter / SoftwareNowPlaying
        // keeps skipForward & skipBackward (±10 s Siri / iPhone Remote skip) enabled on TV episodes
        // as well as movies. Episode advancement is served via on-screen prompts & remote heartbeat.
        engine.setNowPlayingTrackCommands(next: nil, previous: nil)

        guard let artURL = resolvedArtURL, cachedCGImage == nil else {
            return
        }

        let targetSessionID = session.sessionId
        viewModel.sessionController.nowPlayingArtworkTask = Task { @MainActor [weak viewModel] in
            guard let cgImage = await ArtworkPipeline.shared.loadImage(
                url: artURL,
                maxPixelSize: nowPlayingArtworkMaxPixels,
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
        let mediaType = session.item.mediaType == "episode"
            ? MPMediaType.tvShow.rawValue
            : MPMediaType.movie.rawValue
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: meta.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyMediaType: mediaType,
            MPNowPlayingInfoPropertyExternalContentIdentifier: session.item.itemId,
        ]

        if let artist = meta.artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let albumTitle = meta.albumTitle, !albumTitle.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if let duration = session.stream.declaredDurationSeconds ?? session.item.runtimeSeconds,
           duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        return info
    }
}
