import AetherBridge
import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import Luna

final class PlayerTrickplayAndEmbeddedAlignTests: XCTestCase {
    private func makeValidJPEGData(width: Int = 32, height: Int = 18) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        ctx.setFillColor(CGColor(red: 0.78, green: 0.56, blue: 0.28, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(ctx.makeImage())

        let jpegData = NSMutableData()
        let dest = try XCTUnwrap(
            CGImageDestinationCreateWithData(jpegData as CFMutableData, "public.jpeg" as CFString, 1, nil)
        )
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return jpegData as Data
    }

    private func makeSession(
        sessionId: String = "sess-m4a-1",
        source: String = "infinidysk",
        tier: String? = "vfs",
        externalSubtitles: [TvExternalSubtitle]? = nil,
        embeddedSubtitles: [TvSessionEmbeddedSubtitleTrack]? = nil
    ) -> TvPlaybackSession {
        TvPlaybackSession(
            sessionId: sessionId,
            streamToken: "tok-m4a-secret-1234",
            roomName: "Kjellerstua",
            hardwareProfile: "dv-fel-714",
            item: TvPlaybackItemContext(
                itemId: "movie:tmdb:550",
                mediaType: "movie",
                ids: TvMediaIds(tmdb: 550),
                title: "Fight Club",
                runtimeSeconds: 7200
            ),
            selectedCandidate: TvCandidateInfo(
                candidateId: "cand-vfs-1",
                displayHeadline: "4K DV P7 FEL",
                releaseTitle: "Fight.Club.2160p",
                source: source,
                tier: tier,
                resolution: "2160p",
                videoRangeType: "DolbyVision",
                dvProfile: 7,
                dvEnhancementLayer: "FEL",
                audioCodec: "TrueHD",
                sizeBytes: nil,
                tvScore: 1400,
                isActive: true,
                explanationChips: ["VFS", "Dolby Vision"],
                releaseGroup: "FraMeSToR",
                isNorwegian: false
            ),
            stream: TvStreamEndpoint(
                url: "/api/tv/v2/stream/\(sessionId)/tok-m4a-secret-1234/video.mkv",
                declaredDurationSeconds: 7200
            ),
            tracks: TvSessionTracks(
                probeConfidence: "cached_ffprobe",
                video: TvSessionVideoTrack(
                    streamIndex: 0,
                    codec: "hevc",
                    width: 3840,
                    height: 2160,
                    frameRate: 23.976,
                    videoRangeType: "DolbyVision",
                    dvProfile: 7,
                    dvEnhancementLayer: "FEL",
                    hdr10Plus: false
                ),
                audio: [
                    TvSessionAudioTrack(
                        streamIndex: 1,
                        codec: "truehd",
                        spatialFormat: "DolbyAtmos",
                        channels: 8,
                        channelLayout: "7.1",
                        language: "eng",
                        displayTitle: "Atmos",
                        isDefault: true
                    )
                ],
                embeddedSubtitles: embeddedSubtitles,
                externalSubtitles: externalSubtitles,
                subtitleDelayMs: 0
            ),
            aetherConfig: TvAetherConfig(
                preferDualLayerDolbyVision: true,
                dolbyVisionHandling: "automatic",
                matchContentEnabled: true,
                audioBridgeMode: "lossless"
            )
        )
    }

    @MainActor
    func testPlayerScrubControllerServerTrickplayFallbackCachesPerBucketAndHandlesErrorsGracefully() async throws {
        let suite = "luna.v1.test.trickplay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let host = "trickplay-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let jpegBytes = try makeValidJPEGData()
        let requestedBuckets = TestLockedBox<[String]>([])
        MockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "t" })?.value ?? ""
            if url.path.hasSuffix("/scrub-frame") {
                requestedBuckets.withLock { $0.append(t) }
                if t == "120" {
                    let resp = try XCTUnwrap(HTTPURLResponse(
                        url: url, statusCode: 404, httpVersion: nil, headerFields: nil
                    ))
                    return (resp, Data(#"{"ok":false,"code":"scrub_frame_unavailable","error":"Mangler bilde"}"#.utf8))
                }
                if t == "240" {
                    let resp = try XCTUnwrap(HTTPURLResponse(
                        url: url, statusCode: 404, httpVersion: nil, headerFields: nil
                    ))
                    return (resp, Data(#"{"ok":false,"code":"archive_spindown_protected","error":"Arkiv"}"#.utf8))
                }
                let resp = try XCTUnwrap(HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "image/jpeg", "X-Trickplay-Cache": "MISS"]
                ))
                return (resp, jpegBytes)
            }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = FakePlayerTransport(state: .paused, playbackPhase: .paused, currentTime: 100)
        let vm = PlayerViewModel(
            engine: engine,
            comfort: ComfortPreferences(defaults: defaults),
            transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            bindOnInit: false
        )
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = makeSession(sessionId: "sess-tp-1")
        vm.isResolving = false
        vm.durationSeconds = 7200

        // Begin scrub at 100s -> bucket 100
        vm.beginTouchScrub()
        for _ in 0..<25 where vm.scrubState.previewImage == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertNotNil(vm.scrubState.previewImage)
        XCTAssertEqual(requestedBuckets.withLock { $0 }, ["100"])

        // Scrub to 120s (temporary 404 scrub_frame_unavailable -> collapses preview without disabling session)
        vm.updateTouchScrub(deltaSeconds: 20)
        for _ in 0..<25 where requestedBuckets.withLock({ $0.count }) < 2 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertNil(vm.scrubState.previewImage)
        XCTAssertNil(vm.fatalError)

        // Return to bucket 100 -> 0 ms RAM cache hit, zero extra HTTP request
        vm.updateTouchScrub(deltaSeconds: -18)
        for _ in 0..<15 where vm.scrubState.previewImage == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(vm.scrubState.previewImage)
        XCTAssertEqual(requestedBuckets.withLock { $0 }, ["100", "120"])

        // Scrub to 240s -> 404 archive_spindown_protected disables session trickplay cleanly
        vm.updateTouchScrub(deltaSeconds: 138)
        for _ in 0..<25 where requestedBuckets.withLock({ $0.count }) < 3 {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertNil(vm.scrubState.previewImage)
        XCTAssertNil(vm.fatalError)

        // Subsequent scrub at 300s makes zero HTTP requests because session is disabled
        vm.updateTouchScrub(deltaSeconds: 60)
        try await Task.sleep(nanoseconds: 140_000_000)
        XCTAssertEqual(requestedBuckets.withLock { $0 }, ["100", "120", "240"])

        // Clearing cache restores trickplay for a new session
        vm.cancelTouchScrub()
        vm.scrubController.clearServerTrickplayCache()
        vm.activeSession = makeSession(sessionId: "sess-tp-2")
        vm.beginTouchScrub()
        for _ in 0..<25 where vm.scrubState.previewImage == nil {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertNotNil(vm.scrubState.previewImage)
        XCTAssertEqual(requestedBuckets.withLock { $0 }, ["100", "120", "240", "100"])
    }

    @MainActor
    func testEmbeddedMKVAutoAlignAndBitmapErrorMappingInPlayerTrackController() async throws {
        let suite = "luna.v1.test.embalign.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let host = "embalign-\(UUID().uuidString.lowercased()).local"
        defer {
            MockURLProtocol.unregister(host: host)
            defaults.removePersistentDomain(forName: suite)
        }

        let capturedBodies = TestLockedBox<[Data]>([])
        let modeBox = TestLockedBox<String>("success")
        MockURLProtocol.register(host: host) { req in
            let url = try XCTUnwrap(req.url)
            if url.path.hasSuffix("/subtitles/auto-align") {
                let data = MockURLProtocol.bodyData(for: req)
                capturedBodies.withLock { $0.append(data) }
                let mode = modeBox.withLock { $0 }
                if mode == "bitmap" {
                    let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 422, httpVersion: nil, headerFields: nil))
                    return (resp, Data(#"{"ok":false,"code":"bitmap_subtitle_not_supported","error":"Bitmap"}"#.utf8))
                }
                if mode == "unaligned" {
                    let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                    let body = #"{"ok":true,"sessionId":"sess-emb-1","applied":false,"appliedToFile":false,"reason":"invalid_extracted_srt"}"#
                    return (resp, Data(body.utf8))
                }
                let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                let body = #"""
                {
                  "ok": true,
                  "sessionId": "sess-emb-1",
                  "applied": true,
                  "appliedToFile": false,
                  "mode": "embedded_ffmpeg_silencedetect",
                  "method": "embedded_ffmpeg_silencedetect",
                  "reason": "audio_activity_aligned",
                  "confidence": 0.84,
                  "offsetMs": 950,
                  "scale": 1,
                  "subtitleDelayMs": 950,
                  "subtitle": null,
                  "embeddedTrack": { "streamIndex": 2, "codec": "subrip", "language": "nob" }
                }
                """#
                return (resp, Data(body.utf8))
            }
            let resp = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (resp, Data(#"{"ok":true}"#.utf8))
        }

        let engine = try LunaApp.makeSharedEngine()
        defer {
            PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
            engine.stop(resetDisplayCriteria: true)
        }

        let transport = FakePlayerTransport(state: .playing, playbackPhase: .playing)
        transport.subtitleTrackDescriptors = [
            SmartTrackDescriptor(id: 0, name: "Norsk (MKV)", codec: "subrip", language: "nob", isExternal: false),
            SmartTrackDescriptor(id: 1, name: "English PGS", codec: "hdmv_pgs_subtitle", language: "eng", isExternal: false),
            SmartTrackDescriptor(id: 9, name: "English (.srt)", codec: "srt", language: "eng", isExternal: true),
        ]
        transport.activeSubtitleTrackIndex = 0

        let prefStore = PlaybackPreferenceStore(suiteName: suite)
        let vm = PlayerViewModel(
            engine: engine,
            comfort: ComfortPreferences(defaults: defaults),
            transport: transport,
            audioActivator: MockNativeAudioActivator { _ in },
            preferenceStore: prefStore,
            bindOnInit: false
        )
        vm.activeClient = try MockURLProtocol.makeClient(host: host)
        vm.activeSession = makeSession(
            sessionId: "sess-emb-1",
            externalSubtitles: [
                TvExternalSubtitle(id: "ext-eng-0", url: "/api/tv/v2/subtitles/sess-emb-1/0/eng.srt", format: "srt", language: "eng", name: "English (.srt)")
            ],
            embeddedSubtitles: [
                TvSessionEmbeddedSubtitleTrack(streamIndex: 2, codec: "subrip", language: "nob", displayTitle: "Norsk (MKV)"),
                TvSessionEmbeddedSubtitleTrack(streamIndex: 3, codec: "hdmv_pgs_subtitle", language: "eng", displayTitle: "English PGS"),
            ]
        )
        vm.trackController.activeSubtitleTrackIndex = 0

        // Even with an external .srt present, aligning embedded track 0 sends subtitleId: nil, trackIndex: 2, applyToFile: false
        let aligned = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertTrue(aligned)
        XCTAssertEqual(transport.reloadCallCount, 0)
        XCTAssertEqual(vm.subtitleDelayMs, 950)
        XCTAssertEqual(prefStore.subtitleDelayMs(forCandidateId: "cand-vfs-1"), 950)
        XCTAssertTrue(vm.trackController.subtitleActionStatusMessage?.contains("Undertekst synkronisert") == true)

        let bodyData0 = try XCTUnwrap(capturedBodies.withLock { $0.first })
        let body0 = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData0) as? [String: Any])
        XCTAssertNil(body0["subtitleId"])
        XCTAssertEqual(body0["trackIndex"] as? Int, 2)
        XCTAssertEqual(body0["applyToFile"] as? Bool, false)

        // applied: false maps raw snake_case reason cleanly to Norwegian
        modeBox.withLock { $0 = "unaligned" }
        let unaligned = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertFalse(unaligned)
        XCTAssertEqual(vm.trackController.subtitleActionStatusMessage, "Kunne ikke lese innebygd undertekst")

        // 422 bitmap_subtitle_not_supported surfaces Norwegian message cleanly
        modeBox.withLock { $0 = "bitmap" }
        vm.trackController.activeSubtitleTrackIndex = 1
        let bitmap = await vm.trackController.performAutoAlignActiveSubtitle()
        XCTAssertFalse(bitmap)
        XCTAssertEqual(
            vm.trackController.subtitleActionStatusMessage,
            "Bildebaserte undertekster (PGS/DVD/DVB) støttes ikke for auto-synk"
        )
    }
}
