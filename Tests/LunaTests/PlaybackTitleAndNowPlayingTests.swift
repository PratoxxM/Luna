import Foundation
import MediaPlayer
import XCTest
@testable import Luna

final class PlaybackTitleAndNowPlayingTests: XCTestCase {
    func testDetailEpisodeCardAndSourcePickerFormatting() {
        let genericEp = TvEpisodeCard(
            itemId: "episode:tmdb:95396:s1:e4",
            seasonNumber: 1,
            episodeNumber: 4,
            title: "Episode 4",
            overview: nil,
            stillUrl: nil,
            airDate: nil,
            isUpcoming: false,
            airDateBadge: nil,
            voteAverage: nil,
            runtimeSeconds: 2700,
            watched: false,
            availability: nil,
            progress: nil
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.episodeCardTitle(episode: genericEp, seriesTitle: "Severance"),
            "Episode 4"
        )

        let e04Ep = TvEpisodeCard(
            itemId: "episode:tmdb:95396:s1:e4",
            seasonNumber: 1,
            episodeNumber: 4,
            title: "E04",
            overview: nil,
            stillUrl: nil,
            airDate: nil,
            isUpcoming: false,
            airDateBadge: nil,
            voteAverage: nil,
            runtimeSeconds: 2700,
            watched: false,
            availability: nil,
            progress: nil
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.episodeCardTitle(episode: e04Ep, seriesTitle: "Severance"),
            "Episode 4"
        )

        let namedEp = TvEpisodeCard(
            itemId: "episode:tmdb:62560:s4:e1",
            seasonNumber: 4,
            episodeNumber: 1,
            title: "401 Unauthorized",
            overview: nil,
            stillUrl: nil,
            airDate: nil,
            isUpcoming: false,
            airDateBadge: nil,
            voteAverage: nil,
            runtimeSeconds: 2700,
            watched: false,
            availability: nil,
            progress: nil
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.episodeCardTitle(episode: namedEp, seriesTitle: "Mr. Robot"),
            "E01 · 401 Unauthorized"
        )

        let genericPicker = SourcePickerContext(
            itemId: "episode:tmdb:95396:s1:e4",
            title: "Episode 4",
            seriesTitle: "Severance"
        )
        XCTAssertEqual(genericPicker.displaySubject, "Severance · S01E04")
        XCTAssertEqual(genericPicker.apiTitle, "")

        let namedPicker = SourcePickerContext(
            itemId: "episode:tmdb:62560:s4:e1",
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot",
            season: 4,
            episode: 1
        )
        XCTAssertEqual(namedPicker.displaySubject, "Mr. Robot · S04E01 · 401 Unauthorized")
        XCTAssertEqual(namedPicker.apiTitle, "401 Unauthorized")
    }

    @MainActor
    func testNowPlayingMetadataAndPlaybackLaunchApiFallbackNeverDuplicateOrSendSeriesTitle() throws {
        let genericSessionJson = #"""
        {
          "sessionId": "sess-np-1",
          "streamToken": "stream-placeholder-token",
          "roomName": "Stua",
          "hardwareProfile": "hdr10-512",
          "item": {
            "itemId": "episode:tmdb:95396:s1:e4",
            "mediaType": "episode",
            "ids": { "tmdb": 95396 },
            "title": "S01E04",
            "seriesTitle": "Severance",
            "season": 1,
            "episode": 4
          },
          "selectedCandidate": {
            "candidateId": "cand-1",
            "displayHeadline": "4K WEB-DL",
            "releaseTitle": "Severance.S01E04.2160p",
            "source": "vfs",
            "tier": "vfs"
          },
          "stream": { "url": "/api/tv/v1/streams/sess-np-1/master" },
          "aetherConfig": {
            "preferDualLayerDolbyVision": false,
            "dolbyVisionHandling": "baseLayerOnly",
            "matchContentEnabled": true,
            "audioBridgeMode": "lossless"
          }
        }
        """#
        let genericSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(genericSessionJson.utf8))
        let genericNowPlaying = PlayerNowPlayingCoordinator.makeBaseInfo(for: genericSession)
        XCTAssertEqual(genericNowPlaying[MPMediaItemPropertyTitle] as? String, "S01E04")
        XCTAssertEqual(genericNowPlaying[MPMediaItemPropertyArtist] as? String, "Severance")
        XCTAssertEqual(genericNowPlaying[MPMediaItemPropertyAlbumTitle] as? String, "Severance")
        XCTAssertEqual(
            genericNowPlaying[MPNowPlayingInfoPropertyMediaType] as? UInt,
            MPNowPlayingInfoMediaType.video.rawValue
        )
        XCTAssertEqual(
            genericNowPlaying[MPMediaItemPropertyMediaType] as? UInt,
            MPMediaType.tvShow.rawValue
        )
        XCTAssertEqual(
            genericNowPlaying[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String,
            "episode:tmdb:95396:s1:e4"
        )

        let movieDurationJson = genericSessionJson
            .replacingOccurrences(of: "\"episode\"", with: "\"movie\"")
            .replacingOccurrences(of: "\"/api/tv/v1/streams/sess-np-1/master\"", with: "\"/api/tv/v1/streams/sess-np-1/master\", \"declaredDurationSeconds\": 5420")
        let movieDurationSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(movieDurationJson.utf8))
        let movieNowPlaying = PlayerNowPlayingCoordinator.makeBaseInfo(for: movieDurationSession)
        XCTAssertEqual(movieNowPlaying[MPMediaItemPropertyMediaType] as? UInt, MPMediaType.movie.rawValue)
        XCTAssertEqual(movieNowPlaying[MPMediaItemPropertyPlaybackDuration] as? Double, 5420)

        let namedSessionJson = genericSessionJson.replacingOccurrences(of: "\"S01E04\"", with: "\"401 Unauthorized\"")
        let namedSession = try JSONDecoder().decode(TvPlaybackSession.self, from: Data(namedSessionJson.utf8))
        let namedNowPlaying = PlayerNowPlayingCoordinator.makeBaseInfo(for: namedSession)
        XCTAssertEqual(namedNowPlaying[MPMediaItemPropertyTitle] as? String, "401 Unauthorized")
        XCTAssertEqual(namedNowPlaying[MPMediaItemPropertyArtist] as? String, "Severance")
        XCTAssertEqual(namedNowPlaying[MPMediaItemPropertyAlbumTitle] as? String, "Severance · S01E04")

        let cardNoEpisodeTitle = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance",
            episodeCode: "S01E04",
            episodeTitle: nil,
            directPlayTarget: TvDirectPlayTarget(
                itemId: "episode:tmdb:95396:s1:e4",
                mediaType: "episode",
                tmdbId: 95396,
                season: 1,
                episode: 4,
                startPositionSeconds: 120,
                mode: "resume"
            ),
            nextUp: TvNextUpPointer(season: 1, episode: 4)
        )
        let target = MediaCardMutator.resolvePlayTarget(for: cardNoEpisodeTitle)
        XCTAssertEqual(target.itemId, "episode:tmdb:95396:s1:e4")
        XCTAssertEqual(target.title, "")
        XCTAssertEqual(target.seriesTitle, "Severance")
        XCTAssertEqual(target.season, 1)
        XCTAssertEqual(target.episode, 4)

        let badRequest = PlaybackLaunchRequest(
            itemId: "episode:tmdb:95396:s1:e4",
            title: "Severance",
            seriesTitle: "Severance"
        )
        XCTAssertEqual(badRequest.season, 1)
        XCTAssertEqual(badRequest.episode, 4)
        XCTAssertEqual(badRequest.formattedEpisodeCode, "S01E04")
        XCTAssertEqual(badRequest.apiTitle, "")

        let numericRequest = PlaybackLaunchRequest(
            itemId: "episode:tmdb:62560:s4:e1",
            title: "401 Unauthorized",
            seriesTitle: "Mr. Robot"
        )
        XCTAssertEqual(numericRequest.apiTitle, "401 Unauthorized")

        XCTAssertEqual(
            EpisodeTitleFormatter.apiEpisodeTitle(
                rawTitle: "Severance",
                seriesTitle: "Severance",
                itemId: "episode:tmdb:95396:s1:e4",
                season: nil,
                episode: nil
            ),
            ""
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.apiEpisodeTitle(
                rawTitle: "Ukjent",
                seriesTitle: "Severance",
                itemId: "episode:tmdb:95396:s1:e4",
                season: 1,
                episode: 4
            ),
            ""
        )
        XCTAssertEqual(
            EpisodeTitleFormatter.apiEpisodeTitle(
                rawTitle: "1917",
                seriesTitle: nil,
                itemId: "movie:tmdb:530915",
                season: nil,
                episode: nil
            ),
            "1917"
        )

        let nextUpCard = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance",
            episodeCode: "S01E04",
            episodeTitle: "Episode 4",
            nextUp: TvNextUpPointer(season: 1, episode: 4)
        )
        let nextUpTarget = MediaCardMutator.resolvePlayTarget(for: nextUpCard)
        XCTAssertEqual(nextUpTarget.title, "")
        XCTAssertEqual(nextUpTarget.seriesTitle, "Severance")
        XCTAssertEqual(nextUpTarget.season, 1)
        XCTAssertEqual(nextUpTarget.episode, 4)

        let bareSeriesCard = TvMediaCard(
            itemId: "series:tmdb:95396",
            mediaType: "series",
            ids: TvMediaIds(tmdb: 95396),
            title: "Severance"
        )
        let bareSeriesTarget = MediaCardMutator.resolvePlayTarget(for: bareSeriesCard)
        XCTAssertEqual(bareSeriesTarget.title, "")
        XCTAssertEqual(bareSeriesTarget.seriesTitle, "Severance")

        let movieCard = TvMediaCard(
            itemId: "movie:tmdb:530915",
            mediaType: "movie",
            ids: TvMediaIds(tmdb: 530915),
            title: "1917"
        )
        let movieTarget = MediaCardMutator.resolvePlayTarget(for: movieCard)
        XCTAssertEqual(movieTarget.title, "1917")
        XCTAssertNil(movieTarget.seriesTitle)
    }
}
