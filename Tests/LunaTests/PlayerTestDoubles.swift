import AetherBridge
import Foundation
import Synchronization
import XCTest
@testable import Luna

@MainActor
final class MockPlayerTransport: PlayerTransportControlling {
    var state: PlaybackState
    var playbackPhase: PlaybackPhase
    var videoRoute: VideoRoute
    var currentTime: Double
    var needsForegroundVideoRestore: Bool
    var events: [String] = []

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onSeek: ((Double, Bool) async -> Void)?
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
        if state == .playing {
            pause()
        } else {
            play()
        }
    }

    func seek(to seconds: Double, exact: Bool) async {
        currentTime = seconds
        events.append("seek(\(Int(seconds)),\(exact))")
        if let onSeek {
            await onSeek(seconds, exact)
        }
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
        registerAsync(host: host) { req in
            try handler(req)
        }
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
            appVersion: "2.6.0",
            osVersion: "tvOS 26.0",
            session: session,
            imageSession: session
        )
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return handlers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recordedRequests.withLock { $0[host, default: []].append(request) }
        let taskKey = ObjectIdentifier(self)
        let context = MockProtocolDeliveryContext(
            urlProtocol: self,
            client: client,
            request: request
        )
        Self.activeTasks.withLock { map in
            map[taskKey] = Task.detached(priority: .userInitiated) {
                defer { _ = Self.activeTasks.withLock { $0.removeValue(forKey: taskKey) } }
                do {
                    let (response, data) = try await handler(context.request)
                    guard !Task.isCancelled else { return }
                    context.client?.urlProtocol(
                        context.urlProtocol,
                        didReceive: response,
                        cacheStoragePolicy: .notAllowed
                    )
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
