import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Synchronization
@testable import LunaCore

// MARK: - Shared Thread-Safe Box

final class CoreLockedBox<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ initial: Value) {
        self.mutex = Mutex(initial)
    }

    func get() -> Value {
        mutex.withLock { $0 }
    }

    func set(_ newValue: Value) {
        mutex.withLock { $0 = newValue }
    }

    @discardableResult
    func withLock<R, E: Error>(_ body: (inout sending Value) throws(E) -> sending R) throws(E) -> sending R {
        try mutex.withLock(body)
    }
}

// MARK: - Shared Linux-Safe URLProtocol Test Double

private final class UncheckedTransfer<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

final class LunaCoreMockURLProtocol: URLProtocol {
    typealias SyncHandler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private struct HostEntry: Sendable {
        let handler: SyncHandler
        let background: Bool
    }

    private static let entries = Mutex<[String: HostEntry]>([:])
    private static let recordedRequests = Mutex<[String: [URLRequest]]>([:])
    private let stoppedState = Mutex(false)

    static func register(
        host: String,
        background: Bool = false,
        handler: @escaping SyncHandler
    ) {
        let key = host.lowercased()
        entries.withLock { $0[key] = HostEntry(handler: handler, background: background) }
        recordedRequests.withLock { $0[key] = [] }
    }

    static func unregister(host: String) {
        let key = host.lowercased()
        _ = entries.withLock { $0.removeValue(forKey: key) }
        _ = recordedRequests.withLock { $0.removeValue(forKey: key) }
    }

    static func requests(for host: String) -> [URLRequest] {
        recordedRequests.withLock { $0[host.lowercased()] ?? [] }
    }

    static func bodyData(for request: URLRequest) -> Data {
        if let data = request.httpBody {
            return data
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            out.append(buffer, count: count)
        }
        return out
    }

    static func bodyString(for request: URLRequest) -> String {
        String(data: bodyData(for: request), encoding: .utf8) ?? ""
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LunaCoreMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func makeClient(
        host: String,
        scheme: String = "https",
        port: Int = 8920,
        deviceID: String = "luna-core-test-device",
        deviceToken: String? = "tok-core-test-device",
        roomName: String = "Kjellerstua",
        hardwareProfile: String = "dv-fel-714",
        allowSelfSignedLanTLS: Bool = true
    ) -> LunaCoreClient {
        let session = makeSession()
        let baseURL = URL(string: "\(scheme)://\(host):\(port)")!
        return LunaCoreClient(
            baseURL: baseURL,
            deviceID: deviceID,
            deviceToken: deviceToken,
            roomName: roomName,
            hardwareProfile: hardwareProfile,
            allowSelfSignedLanTLS: allowSelfSignedLanTLS,
            appVersion: SideloadSafeStorage.currentAppVersionString(),
            osVersion: "tvOS 26.0",
            session: session,
            imageSession: session,
            externalImageSession: session
        )
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return entries.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host?.lowercased(),
              let entry = Self.entries.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recordedRequests.withLock { $0[host, default: []].append(request) }

        if entry.background {
            let protoBox = UncheckedTransfer(self)
            let reqBox = UncheckedTransfer(request)
            let handler = entry.handler
            DispatchQueue.global().async {
                let proto = protoBox.value
                do {
                    let (response, data) = try handler(reqBox.value)
                    proto.stoppedState.withLock { stopped in
                        guard !stopped else { return }
                        proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
                        proto.client?.urlProtocol(proto, didLoad: data)
                        proto.client?.urlProtocolDidFinishLoading(proto)
                    }
                } catch {
                    proto.stoppedState.withLock { stopped in
                        guard !stopped else { return }
                        proto.client?.urlProtocol(proto, didFailWithError: error)
                    }
                }
            }
            return
        }

        do {
            let (response, data) = try entry.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        stoppedState.withLock { $0 = true }
    }
}

// MARK: - Wire Suspension Gate for Race Tests

final class WireGate: Sendable {
    private let entered = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let didEnter = Mutex(false)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func waitUntilRequestOnWire() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alreadyEntered = didEnter.withLock { enteredFlag -> Bool in
                if enteredFlag { return true }
                entered.withLock { $0 = cont }
                return false
            }
            if alreadyEntered {
                cont.resume()
            }
        }
    }

    func suspendHandlerOnWire() {
        let cont = didEnter.withLock { flag -> CheckedContinuation<Void, Never>? in
            flag = true
            return entered.withLock { c in
                let saved = c
                c = nil
                return saved
            }
        }
        cont?.resume()
        _ = releaseSemaphore.wait(timeout: .now() + .seconds(5))
    }

    func release() {
        releaseSemaphore.signal()
    }
}

// MARK: - Cross-Worker DiskSWRStore Gate

actor DiskSWRTestGate {
    static let shared = DiskSWRTestGate()
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        while isLocked {
            await withCheckedContinuation { waiters.append($0) }
        }
        isLocked = true
        defer {
            isLocked = false
            if !waiters.isEmpty {
                waiters.removeFirst().resume()
            }
        }
        let lockPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("luna-diskswr-test.lock")
            .path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 {
            while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        return try await operation()
    }
}
