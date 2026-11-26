import Foundation
import Observation

@MainActor
@Observable
public final class PairingViewModel {
    public var manualURLInput: String = ""
    public var showManualInput: Bool = false
    public private(set) var selectedBaseURL: URL?
    public private(set) var selectedLocalHostnameURL: URL?
    public private(set) var pairingInfo: TvPairingRequestResponse?
    public var errorMessage: String?
    public private(set) var isRequestingCode: Bool = false
    public private(set) var isCodeExpired: Bool = false

    public let discovery: any ServerDiscoveryProviding

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pollGeneration: UInt64 = 0

    public init(discovery: any ServerDiscoveryProviding) {
        self.discovery = discovery
    }

    public var discoveredServers: [DiscoveredLunaCoreServer] {
        discovery.servers
    }

    public func startDiscovery() {
        discovery.start()
    }

    public func stopDiscovery() {
        pollTask?.cancel()
        pollTask = nil
        pollGeneration &+= 1
        isRequestingCode = false
        discovery.stop()
    }

    public func handleDiscoveredServers(
        _ discovered: [DiscoveredLunaCoreServer],
        session: any PairingSessionContext
    ) {
        guard selectedBaseURL == nil,
              pairingInfo == nil,
              discovered.count == 1,
              let onlyServer = discovered.first,
              !showManualInput else {
            return
        }
        startPairing(
            against: onlyServer.baseURL,
            localHostnameURL: onlyServer.localHostnameURL,
            session: session
        )
    }

    public func submitManualURL(session: any PairingSessionContext) {
        guard !isRequestingCode else { return }
        guard let normalized = ServerFailoverPolicy.normalizeServerURL(manualURLInput) else {
            errorMessage = "Oppgi en gyldig http:// eller https:// adresse."
            return
        }
        startPairing(against: normalized, session: session)
    }

    public func resetServerSelection() {
        pollTask?.cancel()
        pollTask = nil
        pollGeneration &+= 1
        pairingInfo = nil
        selectedBaseURL = nil
        selectedLocalHostnameURL = nil
        isRequestingCode = false
        isCodeExpired = false
        errorMessage = nil
        showManualInput = true
    }

    static func pollSleepNanoseconds(pollIntervalSeconds: Int?, multiplier: UInt64 = 1) -> UInt64 {
        let interval = min(300, max(2, pollIntervalSeconds ?? 3))
        let safeMultiplier = min(10, max(1, multiplier))
        return UInt64(interval) * 1_000_000_000 * safeMultiplier
    }

    @discardableResult
    public func startPairing(
        against baseURL: URL,
        localHostnameURL: URL? = nil,
        session: any PairingSessionContext,
        pollIntervalOverrideNanoseconds: UInt64? = nil
    ) -> Task<Void, Never> {
        pollTask?.cancel()
        pollGeneration &+= 1
        let gen = pollGeneration

        errorMessage = nil
        isCodeExpired = false
        selectedBaseURL = baseURL
        selectedLocalHostnameURL = localHostnameURL
        isRequestingCode = true

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let client = session.makePairingClient(baseURL: baseURL) else {
                self.isRequestingCode = false
                self.errorMessage = "Kunne ikke opprette klient mot \(baseURL.absoluteString)."
                return
            }

            do {
                let meta = session.deviceMetadata
                let info = try await client.requestPairingCode(
                    model: meta.model,
                    osVersion: meta.osVersion,
                    appVersion: meta.appVersion,
                    capabilities: DeviceHardwareCapabilities.asTvCapabilities
                )
                guard !Task.isCancelled, gen == self.pollGeneration else {
                    if gen == self.pollGeneration {
                        self.isRequestingCode = false
                    }
                    return
                }
                self.pairingInfo = info
                self.isRequestingCode = false

                let sleepNs = pollIntervalOverrideNanoseconds
                    ?? Self.pollSleepNanoseconds(pollIntervalSeconds: info.pollIntervalSeconds, multiplier: 1)
                var consecutivePollFailures = 0

                while !Task.isCancelled, gen == self.pollGeneration {
                    if sleepNs > 0 {
                        try? await Task.sleep(nanoseconds: sleepNs)
                    }
                    guard !Task.isCancelled, gen == self.pollGeneration else { return }

                    do {
                        let (httpStatus, poll) = try await client.pollPairingCode(info.pairingCode)
                        guard !Task.isCancelled, gen == self.pollGeneration else { return }
                        consecutivePollFailures = 0

                        if poll.status == "approved",
                           let token = poll.deviceToken,
                           let pairedDevice = poll.device {
                            session.completePairing(
                                baseURL: baseURL,
                                token: token,
                                pairedDevice: pairedDevice,
                                localHostnameURL: localHostnameURL
                            )
                            return
                        }
                        if httpStatus == 404 || httpStatus == 410 || poll.status == "expired" {
                            self.isCodeExpired = true
                            self.errorMessage = "Paringskoden utløp eller ble brukt. Trykk «Ny kode» for å hente en ny."
                            return
                        }
                        if httpStatus == 429 || poll.status == "rate_limited" {
                            let backoffNs = pollIntervalOverrideNanoseconds
                                ?? Self.pollSleepNanoseconds(pollIntervalSeconds: info.pollIntervalSeconds, multiplier: 2)
                            if backoffNs > 0 {
                                try? await Task.sleep(nanoseconds: backoffNs)
                            }
                            continue
                        }
                        if httpStatus == 400 || poll.status == "invalid" {
                            self.isCodeExpired = true
                            self.pairingInfo = nil
                            self.errorMessage = poll.error ?? "Ugyldig paringskode. Trykk «Ny kode» for å prøve igjen."
                            return
                        }
                    } catch {
                        if LunaCoreError.isCancellation(error) || Task.isCancelled || gen != self.pollGeneration {
                            return
                        }
                        consecutivePollFailures += 1
                        if consecutivePollFailures >= 8, !Task.isCancelled, gen == self.pollGeneration {
                            self.errorMessage = "Midlertidig nettverksbrudd mot LunaCore. Prøver fortsatt…"
                        }
                    }
                }
            } catch {
                if gen == self.pollGeneration {
                    self.isRequestingCode = false
                }
                if !Task.isCancelled, gen == self.pollGeneration {
                    self.pairingInfo = nil
                    self.errorMessage = LunaCopy.friendlyErrorMessage(
                        error,
                        fallback: "Kunne ikke kontakte LunaCore på \(baseURL.absoluteString)."
                    )
                }
            }
        }
        pollTask = task
        return task
    }
}
