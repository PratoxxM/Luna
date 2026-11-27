import Foundation
import Observation

extension ServerSessionCore {
    @discardableResult
    public func probeAndFailoverServerURLIfNeeded(timeoutSeconds: TimeInterval = 3.0) async -> Bool {
        guard isPaired, let currentPrimary = serverBaseURL else { return false }
        let startEpoch = pairingEpoch
        let candidates = ServerFailoverPolicy.orderedFailoverCandidates(
            primary: currentPrimary,
            localHostnameURL: serverLocalHostnameURL,
            fallbackServerURL: fallbackServerURL
        )
        guard !candidates.isEmpty else { return false }

        for candidate in candidates {
            guard !Task.isCancelled,
                  isPaired,
                  pairingEpoch == startEpoch,
                  serverBaseURL == currentPrimary else {
                return false
            }
            guard let probeClient = makeClient(overrideBaseURL: candidate) else {
                continue
            }
            do {
                let boot = try await probeClient.probeReachability(timeoutSeconds: timeoutSeconds)
                guard !Task.isCancelled,
                      isPaired,
                      pairingEpoch == startEpoch,
                      serverBaseURL == currentPrimary else {
                    return false
                }
                self.serverBaseURL = candidate
                defaults.set(candidate.absoluteString, forKey: SideloadSafeStorage.serverURLKey)
                applyEngineTLSPolicy()
                rebuildCachedClient()
                syncFromBootstrap(boot.device, defaultRooms: boot.defaultRooms)
                homeRefreshNonce &+= 1
                return true
            } catch LunaCoreError.unauthorized {
                guard !Task.isCancelled,
                      isPaired,
                      pairingEpoch == startEpoch else {
                    return false
                }
                unpairDevice()
                return false
            } catch {
                guard !Task.isCancelled,
                      isPaired,
                      pairingEpoch == startEpoch else {
                    return false
                }
                continue
            }
        }
        return false
    }

    public func syncFromBootstrap(_ device: TvPairedDeviceInfo, defaultRooms: [TvRoomDefinition]? = nil) {
        var clientInputsChanged = false
        if device.deviceName != deviceName {
            self.deviceName = device.deviceName
            defaults.set(device.deviceName, forKey: SideloadSafeStorage.deviceNameKey)
        }
        let nextUnassigned = device.roomUnassigned ?? false
        if nextUnassigned != isRoomUnassigned {
            self.isRoomUnassigned = nextUnassigned
        }
        if device.roomName != roomName {
            self.roomName = device.roomName
            defaults.set(device.roomName, forKey: SideloadSafeStorage.roomNameKey)
            clientInputsChanged = true
        }
        if device.hardwareProfile != hardwareProfile {
            self.hardwareProfile = device.hardwareProfile
            defaults.set(device.hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
            clientInputsChanged = true
        }
        let nextExplicit = device.hardwareProfileExplicit ?? true
        if nextExplicit != isHardwareProfileExplicit {
            self.isHardwareProfileExplicit = nextExplicit
        }
        if device.atmosphere != serverAtmosphere {
            self.serverAtmosphere = device.atmosphere
        }
        if device.equipmentLabel != serverEquipmentLabel {
            self.serverEquipmentLabel = device.equipmentLabel
        }
        if device.speakerLayout != serverSpeakerLayout {
            self.serverSpeakerLayout = device.speakerLayout
        }
        if overrideSyncTask == nil {
            self.comfort.adoptServerOverrides(device.overrides)
        }
        if let defaultRooms, !defaultRooms.isEmpty, defaultRooms != availableRooms {
            self.availableRooms = defaultRooms
        }
        syncComfortRoomSpeakerLayout()
        if clientInputsChanged || cachedClient == nil {
            rebuildCachedClient()
        }
        let localCaps = DeviceHardwareCapabilities.asTvCapabilities
        if !didSyncCapabilitiesThisLaunch, device.capabilities != localCaps, let client = makeClient() {
            didSyncCapabilitiesThisLaunch = true
            capabilitiesSyncTask?.cancel()
            let startEpoch = pairingEpoch
            capabilitiesSyncTask = Task { @MainActor [weak self] in
                guard let self, self.pairingEpoch == startEpoch else { return }
                await self.performProfileSync(context: "capabilities") {
                    try await client.updateDeviceProfile(capabilities: localCaps)
                }
                if !Task.isCancelled, self.pairingEpoch == startEpoch {
                    self.capabilitiesSyncTask = nil
                }
            }
        } else if device.capabilities == localCaps {
            didSyncCapabilitiesThisLaunch = true
        }
    }

    public func setRoomAndProfile(roomName: String, hardwareProfile: String) {
        self.roomName = roomName
        self.isRoomUnassigned = false
        self.hardwareProfile = hardwareProfile
        self.isHardwareProfileExplicit = true
        let matchedRoom = availableRooms.first {
            $0.roomName == roomName && $0.hardwareProfile == hardwareProfile
        } ?? availableRooms.first { $0.hardwareProfile == hardwareProfile }
        self.serverAtmosphere = matchedRoom?.atmosphere
        self.serverEquipmentLabel = matchedRoom?.equipmentLabel
        self.serverSpeakerLayout = matchedRoom?.speakerLayout
        syncComfortRoomSpeakerLayout()
        defaults.set(roomName, forKey: SideloadSafeStorage.roomNameKey)
        defaults.set(hardwareProfile, forKey: SideloadSafeStorage.hardwareProfileKey)
        profileSyncTask?.cancel()
        profileSyncTask = nil
        rebuildCachedClient()
        if let client = makeClient() {
            let localCaps = DeviceHardwareCapabilities.asTvCapabilities
            let startEpoch = pairingEpoch
            profileSyncTask = Task { @MainActor [weak self] in
                guard let self, self.pairingEpoch == startEpoch else { return }
                await self.performProfileSync(context: "room_and_profile") {
                    try await client.updateDeviceProfile(
                        roomName: roomName,
                        hardwareProfile: hardwareProfile,
                        capabilities: localCaps
                    )
                }
                if !Task.isCancelled, self.pairingEpoch == startEpoch {
                    self.profileSyncTask = nil
                }
            }
        }
        homeRefreshNonce &+= 1
    }

    public func refreshProfileFromServer() async {
        guard isPaired else { return }
        let startEpoch = pairingEpoch
        let previousRoom = roomName
        let previousProfile = hardwareProfile
        if let client = makeClient() {
            do {
                let boot = try await client.fetchBootstrap()
                guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
                syncFromBootstrap(boot.device, defaultRooms: boot.defaultRooms)
            } catch LunaCoreError.unauthorized {
                guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
                unpairDevice()
                return
            } catch where ServerFailoverPolicy.isFailoverEligibleError(error) {
                guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
                if await probeAndFailoverServerURLIfNeeded() {
                    return
                }
                guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
            } catch {
                // Keep cached server values until next bootstrap succeeds
            }
        }
        guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
        if roomName != previousRoom || hardwareProfile != previousProfile {
            homeRefreshNonce &+= 1
        }
    }

    internal func performProfileSync(
        context: String,
        operation: () async throws -> Void
    ) async {
        let startEpoch = pairingEpoch
        guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
        do {
            try await operation()
            guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
        } catch where LunaCoreError.isCancellation(error) {
            return
        } catch LunaCoreError.unauthorized {
            guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
            unpairDevice()
        } catch {
            guard !Task.isCancelled, isPaired, pairingEpoch == startEpoch else { return }
            platform.logNonFatalWarning(Self.redactedProfileSyncWarning(context: context, error: error))
        }
    }

    internal nonisolated static func redactedProfileSyncWarning(context: String, error: any Error) -> String {
        let reason: String
        if let lcError = error as? LunaCoreError {
            switch lcError {
            case .unauthorized:
                reason = "unauthorized"
            case .serverMessage(let status, _):
                reason = "http_status=\(status)"
            case .decodingFailed:
                reason = "decoding_failed"
            case .invalidURL:
                reason = "invalid_url"
            }
        } else if let urlError = error as? URLError {
            reason = "url_error=\(urlError.code.rawValue)"
        } else {
            let nsError = error as NSError
            reason = "error_domain=\(nsError.domain) code=\(nsError.code)"
        }
        return "device_profile_sync_failed context=\(context) \(reason)"
    }
}

extension ServerSessionCore: TabSessionContext, SearchSessionContext, PairingSessionContext {
    public var hasActivePlayback: Bool {
        activePlaybackTarget != nil
    }

    public func makeHomeClient() -> (any HomeClientProviding)? {
        makeClient()
    }

    public func makeCatalogClient() -> (any CatalogClientProviding)? {
        makeClient()
    }

    public func makeLibraryClient() -> (any LibraryClientProviding)? {
        makeClient()
    }

    public func makeSearchClient() -> (any SearchClientProviding)? {
        makeClient()
    }

    public func probeAndFailoverServerURLIfNeeded() async -> Bool {
        await probeAndFailoverServerURLIfNeeded(timeoutSeconds: 3.0)
    }

    public var deviceMetadata: PairingDeviceMetadata {
        PairingDeviceMetadata(
            model: platform.hardwareModelString(),
            osVersion: platform.systemVersionString(),
            appVersion: platform.appVersionString()
        )
    }

    public func makePairingClient(baseURL: URL) -> (any PairingClientProviding)? {
        makeClient(overrideBaseURL: baseURL)
    }
}
