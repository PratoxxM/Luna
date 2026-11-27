import AetherBridge
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import XCTest
@testable import Luna

typealias FakePlayerTransport = MockPlayerTransport

@MainActor
final class MockPlayerTransport: PlayerTransportControlling {
    var state: PlaybackState
    var playbackPhase: PlaybackPhase
    var videoRoute: VideoRoute
    var currentTime: Double
    var needsForegroundVideoRestore: Bool
    var audioTrackDescriptors: [PlaybackAudioTrackDescriptor] = []
    var activeAudioTrackIndex: Int?
    var subtitleTrackDescriptors: [SmartTrackDescriptor] = []
    var activeSubtitleTrackIndex: Int?
    var events: [String] = []
    var lastAudioDelaySeconds: Double?
    var lastAudioShaping: AudioShaping?
    var lastSubtitleDelaySeconds: Double?
    var lastLoadedURL: URL?
    var lastLoadedStartPosition: Double?
    var lastLoadedOptions: LoadOptions?
    var lastReloadedOptions: LoadOptions?
    var reloadCallCount: Int = 0
    var heldPictureFrameWaitSeconds: Double = 0
    var attachedStillView: AetherStillView?
    var isHoldingOutgoingPicture: Bool = false
    var holdOutgoingPictureCallCount: Int = 0
    var releaseOutgoingPictureCallCount: Int = 0
    var holdOutgoingPictureResult: Bool = true

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSeek: ((Double, Bool) async -> Void)?
    var onSetAudioDelay: ((Double) -> Void)?
    var onHoldOutgoingPicture: (() async -> Bool)?
    var onReleaseOutgoingPicture: (() -> Void)?
    var onLoadStream: ((URL, Double?, LoadOptions) async throws -> Void)?
    var onReloadAtCurrentPosition: ((inout LoadOptions) throws -> Void)?
    var onStop: ((Bool, Bool) -> Void)?

    init(
        state: PlaybackState = .idle,
        playbackPhase: PlaybackPhase = .idle,
        videoRoute: VideoRoute = .loopback,
        currentTime: Double = 0,
        needsForegroundVideoRestore: Bool = false
    ) {
        self.state = state
        self.playbackPhase = playbackPhase
        self.videoRoute = videoRoute
        self.currentTime = currentTime
        self.needsForegroundVideoRestore = needsForegroundVideoRestore
    }

    func play() {
        state = .playing
        playbackPhase = .playing
        events.append("play")
        onPlay?()
    }

    func pause() {
        state = .paused
        playbackPhase = .paused
        events.append("pause")
        onPause?()
    }

    func togglePlayPause() {
        if state == .playing { pause() } else { play() }
    }

    func seek(to seconds: Double, exact: Bool) async {
        currentTime = seconds
        events.append("seek(\(Int(seconds)),\(exact))")
        if let onSeek { await onSeek(seconds, exact) }
    }

    func setAudioDelay(_ seconds: Double) {
        lastAudioDelaySeconds = seconds
        events.append("audioDelay(\(Int((seconds * 1000.0).rounded()))ms)")
        onSetAudioDelay?(seconds)
    }

    func setAudioShaping(_ shaping: AudioShaping) {
        lastAudioShaping = shaping
        events.append("audioShaping(\(shaping.dialogueGainDB))")
    }

    func setSoftwareSubtitleDelay(_ seconds: Double) {
        lastSubtitleDelaySeconds = seconds
        events.append("subtitleDelay(\(Int((seconds * 1000.0).rounded()))ms)")
    }

    func selectAudioTrack(index: Int) {
        activeAudioTrackIndex = index
        events.append("selectAudio(\(index))")
    }

    func selectSubtitleTrack(index: Int) {
        activeSubtitleTrackIndex = index
        events.append("selectSubtitle(\(index))")
    }

    func clearSubtitle() {
        activeSubtitleTrackIndex = nil
        events.append("clearSubtitle")
    }

    func attachStillView(_ view: AetherStillView?) {
        attachedStillView = view
        events.append(view == nil ? "detachStillView" : "attachStillView")
    }

    @discardableResult
    func holdOutgoingPicture() async -> Bool {
        holdOutgoingPictureCallCount += 1
        events.append("holdOutgoingPicture")
        let held = if let onHoldOutgoingPicture { await onHoldOutgoingPicture() } else { holdOutgoingPictureResult }
        isHoldingOutgoingPicture = held
        return held
    }

    func releaseOutgoingPicture() {
        releaseOutgoingPictureCallCount += 1
        isHoldingOutgoingPicture = false
        events.append("releaseOutgoingPicture")
        onReleaseOutgoingPicture?()
    }

    func prepareForItemReplacement() {
        events.append("prepareForItemReplacement")
    }

    func loadStream(url: URL, startPosition: Double?, options: LoadOptions) async throws {
        lastLoadedURL = url
        lastLoadedStartPosition = startPosition
        lastLoadedOptions = options
        if let startPosition { currentTime = startPosition }
        state = options.autoplay ? .playing : .paused
        playbackPhase = options.autoplay ? .playing : .paused
        events.append("loadStream(\(startPosition.map { String(format: "%.1f", $0) } ?? "nil"))")
        if let onLoadStream { try await onLoadStream(url, startPosition, options) }
    }

    func reloadAtCurrentPosition(applying change: (inout LoadOptions) -> Void) async throws {
        var updated = lastReloadedOptions ?? lastLoadedOptions ?? LoadOptions()
        change(&updated)
        if let onReloadAtCurrentPosition { try onReloadAtCurrentPosition(&updated) }
        lastReloadedOptions = updated
        lastLoadedOptions = updated
        reloadCallCount += 1
        events.append("reloadAtCurrentPosition")
    }

    func stop(resetDisplayCriteria: Bool, finalTeardown: Bool) {
        state = .idle
        playbackPhase = .idle
        events.append("stop(\(resetDisplayCriteria),\(finalTeardown))")
        onStop?(resetDisplayCriteria, finalTeardown)
    }
}

struct MockNativeAudioActivator: NativeAudioActivating {
    let handler: @Sendable (VideoRoute) async -> Void

    func activateNativePlaybackIfNeeded(videoRoute: VideoRoute) async {
        await handler(videoRoute)
    }
}

final class TestLockedBox<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ initialValue: Value) {
        self.storage = Mutex(initialValue)
    }

    func withLock<Result, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending Result
    ) throws(E) -> sending Result {
        try storage.withLock(body)
    }
}

actor TestStepGate {
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseGate: CheckedContinuation<Void, Never>?
    private var started = false

    func reset() {
        startWaiter = nil
        releaseGate = nil
        started = false
    }

    func wait(label: String, log: TestLockedBox<[String]>) async {
        log.withLock { $0.append("\(label)_start") }
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseGate = $0 }
        log.withLock { $0.append("\(label)_end") }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() {
        releaseGate?.resume()
        releaseGate = nil
    }
}

final class IsolatedDefaultsScope {
    let suiteName: String
    let defaults: UserDefaults

    init(prefix: String = "luna.v1.test") throws {
        let name = "\(prefix).\(UUID().uuidString)"
        self.suiteName = name
        self.defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
final class SharedTestEngineScope {
    let engine: AetherEngine

    init(configured: Bool = true) throws {
        self.engine = configured ? try LunaApp.makeSharedEngine() : try AetherEngine()
    }

    func stop() {
        PlayerAudioSessionCoordinator.shared.cancelDeferredDisplayCriteriaReset()
        engine.stop(resetDisplayCriteria: true)
    }
}

enum PlayerTestFixtures {
    static func makeMovieSession(
        sessionId: String = "sess-movie-1",
        streamToken: String = "tok-stream-secret-12345678",
        roomName: String = "Kjellerstua",
        hardwareProfile: String = "dv-fel-714",
        itemId: String = "movie:tmdb:693134",
        tmdbId: Int = 693134,
        title: String = "Dune: Part Two",
        originalLanguage: String? = nil,
        runtimeSeconds: Double? = 9960,
        candidateId: String = "cand-1",
        headline: String = "4K HDR10+ TrueHD Atmos",
        releaseTitle: String = "Dune.Part.Two.2160p",
        source: String = "nvme",
        tier: String? = "nvme",
        resolution: String? = "2160p",
        videoRangeType: String? = "HDR10",
        videoCodec: String? = "hevc",
        dvProfile: Int? = nil,
        dvEnhancementLayer: String? = nil,
        sizeBytes: Int64? = nil,
        startPositionSeconds: Double? = nil,
        declaredDurationSeconds: Double? = nil,
        supportsByteRanges: Bool? = true,
        canClientPrewarmBytes: Bool? = nil,
        tracks: TvSessionTracks? = nil,
        preferDualLayerDolbyVision: Bool = false,
        foldsDolbyVisionFEL: Bool? = nil,
        dolbyVisionHandling: String = "automatic",
        objectAudioLayout: String? = nil,
        skipsContainerAttachments: Bool? = nil,
        generatesBackgroundScrubPreviews: Bool? = nil
    ) -> TvPlaybackSession {
        TvPlaybackSession(
            sessionId: sessionId,
            streamToken: streamToken,
            roomName: roomName,
            hardwareProfile: hardwareProfile,
            item: TvPlaybackItemContext(
                itemId: itemId, mediaType: "movie", ids: TvMediaIds(tmdb: tmdbId),
                title: title, runtimeSeconds: runtimeSeconds, originalLanguage: originalLanguage
            ),
            selectedCandidate: TvCandidateInfo(
                candidateId: candidateId, displayHeadline: headline, releaseTitle: releaseTitle,
                source: source, tier: tier, resolution: resolution, videoRangeType: videoRangeType,
                dvProfile: dvProfile, dvEnhancementLayer: dvEnhancementLayer, audioCodec: "TrueHD Atmos",
                sizeBytes: sizeBytes, tvScore: 1200, isActive: true, explanationChips: nil,
                releaseGroup: nil, isNorwegian: false, videoCodec: videoCodec
            ),
            stream: TvStreamEndpoint(
                url: "/api/tv/v2/stream/\(sessionId)/\(streamToken)/video.mkv",
                supportsByteRanges: supportsByteRanges,
                canClientPrewarmBytes: canClientPrewarmBytes,
                startPositionSeconds: startPositionSeconds,
                declaredDurationSeconds: declaredDurationSeconds
            ),
            tracks: tracks,
            aetherConfig: TvAetherConfig(
                preferDualLayerDolbyVision: preferDualLayerDolbyVision,
                foldsDolbyVisionFEL: foldsDolbyVisionFEL,
                dolbyVisionHandling: dolbyVisionHandling,
                matchContentEnabled: true,
                objectAudioRendering: objectAudioLayout.map { TvObjectAudioConfig(mode: "render", layout: $0) },
                audioBridgeMode: "lossless",
                skipsContainerAttachments: skipsContainerAttachments,
                generatesBackgroundScrubPreviews: generatesBackgroundScrubPreviews
            )
        )
    }

    static func makeEpisodeSession(
        sessionId: String = "sess-ep-1",
        streamToken: String = "tok-ep-secret-12345678",
        roomName: String = "Stua",
        hardwareProfile: String = "hdr10-512",
        itemId: String = "episode:tmdb:95396:s2:e3",
        tmdbId: Int = 95396,
        title: String = "Who Is Alive?",
        seriesTitle: String = "Severance",
        season: Int = 2,
        episode: Int = 3,
        runtimeSeconds: Double? = 3180,
        candidateId: String = "cand-ep-1",
        nextEpisode: TvNextEpisodeSummary? = nil
    ) -> TvPlaybackSession {
        TvPlaybackSession(
            sessionId: sessionId,
            streamToken: streamToken,
            roomName: roomName,
            hardwareProfile: hardwareProfile,
            item: TvPlaybackItemContext(
                itemId: itemId, mediaType: "episode", ids: TvMediaIds(tmdb: tmdbId),
                title: title, seriesTitle: seriesTitle, season: season, episode: episode,
                runtimeSeconds: runtimeSeconds
            ),
            selectedCandidate: TvCandidateInfo(
                candidateId: candidateId, displayHeadline: "4K HDR10+", releaseTitle: "Severance.2160p",
                source: "nvme", tier: "nvme", resolution: "2160p", videoRangeType: "HDR10Plus",
                dvProfile: nil, dvEnhancementLayer: nil, audioCodec: "Atmos", sizeBytes: nil,
                tvScore: 1100, isActive: true, explanationChips: nil, releaseGroup: nil, isNorwegian: false
            ),
            stream: TvStreamEndpoint(url: "/api/tv/v2/stream/\(sessionId)/\(streamToken)/video.mkv"),
            aetherConfig: TvAetherConfig(
                preferDualLayerDolbyVision: false, dolbyVisionHandling: "automatic",
                matchContentEnabled: true, audioBridgeMode: "lossless"
            ),
            nextEpisode: nextEpisode
        )
    }

    static func sessionJSONObject(_ session: TvPlaybackSession) throws -> Any {
        let data = try JSONEncoder().encode(session)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func makeImageData(utType: String = "public.png", width: Int = 16, height: Int = 16) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = utType == "public.jpeg"
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: bitmapInfo
            )
        )
        ctx.setFillColor(CGColor(red: 0.80, green: 0.60, blue: 0.32, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out as CFMutableData, utType as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }
}

private struct MockProtocolDeliveryContext: @unchecked Sendable {
    let urlProtocol: MockURLProtocol
    let client: (any URLProtocolClient)?
    let request: URLRequest
}

final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    typealias AsyncHandler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)

    private static let handlers = Mutex<[String: AsyncHandler]>([:])
    private static let recordedRequests = Mutex<[String: [URLRequest]]>([:])
    private static let activeTasks = Mutex<[ObjectIdentifier: Task<Void, Never>]>([:])

    static func register(host: String, handler: @escaping Handler) {
        registerAsync(host: host) { req in try handler(req) }
    }

    static func registerAsync(host: String, handler: @escaping AsyncHandler) {
        let key = host.lowercased()
        handlers.withLock { $0[key] = handler }
        recordedRequests.withLock { $0[key] = [] }
    }

    static func unregister(host: String) {
        let key = host.lowercased()
        _ = handlers.withLock { $0.removeValue(forKey: key) }
        _ = recordedRequests.withLock { $0.removeValue(forKey: key) }
    }

    static func requests(forHost host: String) -> [URLRequest] {
        recordedRequests.withLock { $0[host.lowercased()] ?? [] }
    }

    static func bodyData(for request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return out
    }

    static func makeClient(
        host: String,
        scheme: String = "http",
        port: Int = 8090,
        deviceToken: String? = "test-device-token"
    ) throws -> LunaCoreClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let baseURL = try XCTUnwrap(URL(string: "\(scheme)://\(host):\(port)"))
        return LunaCoreClient(
            baseURL: baseURL,
            deviceID: "luna-test-device",
            deviceToken: deviceToken,
            roomName: "Stua",
            hardwareProfile: "hdr10-512",
            allowSelfSignedLanTLS: true,
            appVersion: SideloadSafeStorage.currentAppVersionString(),
            osVersion: "tvOS 26.0",
            session: session,
            imageSession: session
        )
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recordedRequests.withLock { $0[host, default: []].append(request) }
        let taskKey = ObjectIdentifier(self)
        let context = MockProtocolDeliveryContext(urlProtocol: self, client: client, request: request)
        Self.activeTasks.withLock { map in
            map[taskKey] = Task.detached(priority: .userInitiated) {
                defer { _ = Self.activeTasks.withLock { $0.removeValue(forKey: taskKey) } }
                do {
                    let (response, data) = try await handler(context.request)
                    guard !Task.isCancelled else { return }
                    context.client?.urlProtocol(context.urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
                    context.client?.urlProtocol(context.urlProtocol, didLoad: data)
                    context.client?.urlProtocolDidFinishLoading(context.urlProtocol)
                } catch {
                    guard !Task.isCancelled else { return }
                    context.client?.urlProtocol(context.urlProtocol, didFailWithError: error)
                }
            }
        }
    }

    override func stopLoading() {
        let task = Self.activeTasks.withLock { $0.removeValue(forKey: ObjectIdentifier(self)) }
        task?.cancel()
    }
}
