import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import LunaCore

final class ServerFailoverAndComfortModelsTests: XCTestCase {
    func testBonjourServiceParserDualStackAndApiPathV2Defaults() {
        XCTAssertFalse(BonjourDiscoveryPolicy.restrictsToIPv4Only)
        XCTAssertTrue(BonjourDiscoveryPolicy.allowsIPv4)
        XCTAssertTrue(BonjourDiscoveryPolicy.allowsIPv6)
        XCTAssertEqual(BonjourDiscoveryPolicy.defaultAPIPath, "/api/tv/v2")

        let ipv4 = BonjourServiceParser.parseDiscoveredService(
            id: "svc-v4",
            serviceName: "LunaCore",
            rawHost: "192.0.2.10",
            port: 8090,
            txt: [:]
        )
        XCTAssertEqual(ipv4?.baseURL.absoluteString, "http://192.0.2.10:8090")
        XCTAssertEqual(ipv4?.apiPath, "/api/tv/v2")
        XCTAssertNil(ipv4?.localHostnameURL)

        let ipv6 = BonjourServiceParser.parseDiscoveredService(
            id: "svc-v6",
            serviceName: "LunaCore-v6",
            rawHost: "[2001:db8::10]",
            port: 8090,
            txt: ["https_port": "8920", "hostname": "lunacore"]
        )
        XCTAssertEqual(ipv6?.baseURL.absoluteString, "https://[2001:db8::10]:8920")
        XCTAssertEqual(ipv6?.apiPath, "/api/tv/v2")
        XCTAssertEqual(ipv6?.localHostnameURL?.absoluteString, "https://lunacore.local:8920")

        let customApi = BonjourServiceParser.parseDiscoveredService(
            id: "svc-custom",
            serviceName: "LunaCore",
            rawHost: "lunacore.local",
            port: 8090,
            txt: ["tls_port": "8920", "api": "/api/tv/v2"]
        )
        XCTAssertEqual(customApi?.baseURL.absoluteString, "https://lunacore.local:8920")
        XCTAssertEqual(customApi?.apiPath, "/api/tv/v2")
        XCTAssertEqual(customApi?.localHostnameURL?.absoluteString, "https://lunacore.local:8920")

        // Link-local scope ID must be rejected cleanly
        XCTAssertNil(
            BonjourServiceParser.parseDiscoveredService(
                id: "svc-ll",
                serviceName: "LunaCore",
                rawHost: "[fe80::1%en0]",
                port: 8090,
                txt: [:]
            )
        )
    }

    func testServerFailoverPolicyEligibilityCandidatesNormalizationAndTrust() throws {
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.timedOut)))
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.cannotConnectToHost)))
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.cannotFindHost)))
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.dnsLookupFailed)))
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.networkConnectionLost)))
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.notConnectedToInternet)))
        XCTAssertTrue(ServerFailoverPolicy.isFailoverEligibleError(URLError(.secureConnectionFailed)))

        XCTAssertFalse(ServerFailoverPolicy.isFailoverEligibleError(URLError(.cancelled)))
        XCTAssertFalse(ServerFailoverPolicy.isFailoverEligibleError(URLError(.badURL)))
        XCTAssertFalse(ServerFailoverPolicy.isFailoverEligibleError(LunaCoreError.unauthorized))
        XCTAssertFalse(ServerFailoverPolicy.isFailoverEligibleError(LunaCoreError.serverMessage(503, "Busy")))

        let primaryHTTPS = try XCTUnwrap(URL(string: "https://media.example.test:8920"))
        let localURL = try XCTUnwrap(URL(string: "http://lunacore.local:8090"))
        let fallbackURL = try XCTUnwrap(URL(string: "https://backup.example.test:8920"))
        let candidates = ServerFailoverPolicy.orderedFailoverCandidates(
            primary: primaryHTTPS,
            localHostnameURL: localURL,
            fallbackServerURL: fallbackURL
        )
        XCTAssertEqual(
            candidates.map(\.absoluteString),
            [
                "http://media.example.test:8090",
                "http://lunacore.local:8090",
                "https://backup.example.test:8920",
            ]
        )

        let primaryHTTP = try XCTUnwrap(URL(string: "http://media.example.test:8090"))
        let dedupCandidates = ServerFailoverPolicy.orderedFailoverCandidates(
            primary: primaryHTTP,
            localHostnameURL: URL(string: "HTTP://MEDIA.EXAMPLE.TEST:8090"),
            fallbackServerURL: nil
        )
        XCTAssertEqual(dedupCandidates.map(\.absoluteString), ["https://media.example.test:8920"])

        let ipv6HTTPS = try XCTUnwrap(URL(string: "https://[2001:db8::42]:8920"))
        XCTAssertEqual(
            ServerFailoverPolicy.orderedFailoverCandidates(
                primary: ipv6HTTPS,
                localHostnameURL: nil,
                fallbackServerURL: nil
            ).map(\.absoluteString),
            ["http://[2001:db8::42]:8090"]
        )

        let ipv6HTTP = try XCTUnwrap(URL(string: "http://[2001:db8::42]:8090"))
        XCTAssertEqual(
            ServerFailoverPolicy.orderedFailoverCandidates(
                primary: ipv6HTTP,
                localHostnameURL: nil,
                fallbackServerURL: nil
            ).map(\.absoluteString),
            ["https://[2001:db8::42]:8920"]
        )

        XCTAssertEqual(
            ServerFailoverPolicy.normalizeServerURL("  https://media.example.test:8920/api/tv/v2/ ")?.absoluteString,
            "https://media.example.test:8920"
        )
        XCTAssertEqual(
            ServerFailoverPolicy.normalizeServerURL("media.example.test:8090/api/tv/v1/")?.absoluteString,
            "http://media.example.test:8090"
        )
        XCTAssertNil(ServerFailoverPolicy.normalizeServerURL("   "))
        XCTAssertNil(ServerFailoverPolicy.normalizeServerURL("ftp://media.example.test"))

        XCTAssertTrue(
            ServerFailoverPolicy.shouldTrustServerHost("lunacore.local", configuredHost: nil, allowSelfSignedLanTLS: true)
        )
        XCTAssertFalse(
            ServerFailoverPolicy.shouldTrustServerHost("lunacore.local", configuredHost: nil, allowSelfSignedLanTLS: false)
        )
    }

    func testComfortPreferenceModelsAndHardwarePresets() {
        XCTAssertEqual(HardwareProfilePreset.dvFel714.defaultRoomName, "Kjellerstua")
        XCTAssertEqual(HardwareProfilePreset.hdr10512.defaultRoomName, "Stua")
        XCTAssertEqual(HardwareProfilePreset.fallbackRooms.count, 2)

        XCTAssertEqual(SubtitleFontSizePreset.fromScale(0.85), .small)
        XCTAssertEqual(SubtitleFontSizePreset.fromScale(1.0), .normal)
        XCTAssertEqual(SubtitleFontSizePreset.fromScale(1.2), .large)
        XCTAssertEqual(SubtitleFontSizePreset.small.pointSizeValue, 36)
        XCTAssertEqual(SubtitleFontSizePreset.normal.pointSizeValue, 42)
        XCTAssertEqual(SubtitleFontSizePreset.large.pointSizeValue, 50)

        XCTAssertEqual(SubtitleBoxOpacityPreset.fromAlpha(0.0), .none)
        XCTAssertEqual(SubtitleBoxOpacityPreset.fromAlpha(0.35), .subtle35)
        XCTAssertEqual(SubtitleBoxOpacityPreset.fromAlpha(0.60), .cinema60)

        XCTAssertEqual(SpeakerLayoutOverrideMode.fromStored("5.1.2"), .atmos512)
        XCTAssertEqual(SpeakerLayoutOverrideMode.fromStored("714"), .atmos714)
        XCTAssertEqual(SpeakerLayoutOverrideMode.fromStored("stereo"), .stereo)
        XCTAssertEqual(SpeakerLayoutOverrideMode.fromStored("unknown"), .auto)
        XCTAssertEqual(
            SpeakerLayoutOverrideMode.auto.displayTitle(forHardwareProfile: "hdr10-512"),
            "Auto (5.1.2)"
        )
        XCTAssertEqual(
            SpeakerLayoutOverrideMode.auto.displayTitle(forHardwareProfile: "dv-fel-714"),
            "Auto (7.1.4)"
        )
        XCTAssertEqual(SpeakerLayoutOverrideMode.quickPanelCases, [.auto, .atmos512, .atmos714])

        XCTAssertEqual(LowResUpscaleMode.defaultMode(for: .high2026), .auto)
        XCTAssertEqual(LowResUpscaleMode.defaultMode(for: .standard), .off)
        XCTAssertEqual(LowResUpscaleMode.auto.shortDescription, "MetalFX for < 1080p SDR · 4K og HDR urørt.")
        XCTAssertFalse(LowResUpscaleMode.auto.shortDescription.contains("Kun < 1080p"))
        XCTAssertTrue(DeviceMemoryProfile.defaultFullHDUpscaleEnabled(for: .high2026))
        XCTAssertFalse(DeviceMemoryProfile.defaultFullHDUpscaleEnabled(for: .standard))
        XCTAssertTrue(DeviceMemoryProfile(physicalMemoryBytes: 8 * 1_073_741_824, activeProcessorCount: 6).defaultFullHDUpscaleEnabled)
        XCTAssertFalse(DeviceMemoryProfile(physicalMemoryBytes: 4 * 1_073_741_824, activeProcessorCount: 6).defaultFullHDUpscaleEnabled)

        XCTAssertEqual(
            UpscaleLoadPolicy.resolve(lowResMode: .off, upscalesFullHDVideo: false),
            UpscaleLoadPolicy(upscalesLowResolutionVideo: false, scaler: .automatic, upscalesFullHDVideo: false)
        )
        XCTAssertEqual(
            UpscaleLoadPolicy.resolve(lowResMode: .off, upscalesFullHDVideo: true),
            UpscaleLoadPolicy(upscalesLowResolutionVideo: false, scaler: .lanczos, upscalesFullHDVideo: true)
        )
        XCTAssertEqual(
            UpscaleLoadPolicy.resolve(lowResMode: .auto, upscalesFullHDVideo: false),
            UpscaleLoadPolicy(upscalesLowResolutionVideo: true, scaler: .automatic, upscalesFullHDVideo: false)
        )
        XCTAssertEqual(
            UpscaleLoadPolicy.resolve(lowResMode: .auto, upscalesFullHDVideo: true),
            UpscaleLoadPolicy(upscalesLowResolutionVideo: true, scaler: .automatic, upscalesFullHDVideo: true)
        )
        XCTAssertEqual(
            UpscaleLoadPolicy.resolve(lowResMode: .animeLineArt, upscalesFullHDVideo: false),
            UpscaleLoadPolicy(upscalesLowResolutionVideo: true, scaler: .lineArt, upscalesFullHDVideo: false)
        )
        XCTAssertEqual(
            UpscaleLoadPolicy.resolve(lowResMode: .animeLineArt, upscalesFullHDVideo: true),
            UpscaleLoadPolicy(upscalesLowResolutionVideo: true, scaler: .lineArt, upscalesFullHDVideo: false)
        )

        let fullHDSDR = TvCandidateInfo(
            candidateId: "cand-1080p-sdr", displayHeadline: "1080p SDR", releaseTitle: "Test.1080p.SDR",
            source: "nvme", tier: "nvme", resolution: "1080p", videoRangeType: "SDR",
            dvProfile: nil, dvEnhancementLayer: nil, audioCodec: "EAC3", sizeBytes: nil,
            tvScore: 100, isActive: false, explanationChips: nil, releaseGroup: nil, isNorwegian: false
        )
        XCTAssertTrue(fullHDSDR.isLikelyFullHDSDRForUpscale)
        XCTAssertFalse(fullHDSDR.isLikelySub1080pSDRForUpscale)
        XCTAssertTrue(fullHDSDR.isLikelyLowResolutionSDRForUpscale)

        let subHDSDR = TvCandidateInfo(
            candidateId: "cand-720p-sdr", displayHeadline: "720p SDR", releaseTitle: "Test.720p.SDR",
            source: "nvme", tier: "nvme", resolution: "720p", videoRangeType: "SDR",
            dvProfile: nil, dvEnhancementLayer: nil, audioCodec: "EAC3", sizeBytes: nil,
            tvScore: 100, isActive: false, explanationChips: nil, releaseGroup: nil, isNorwegian: false
        )
        XCTAssertFalse(subHDSDR.isLikelyFullHDSDRForUpscale)
        XCTAssertTrue(subHDSDR.isLikelySub1080pSDRForUpscale)
        XCTAssertTrue(subHDSDR.isLikelyLowResolutionSDRForUpscale)

        XCTAssertEqual(MenuDisplayMode.allCases.count, 3)
        XCTAssertEqual(AudioEnhancementMode.allCases.count, 3)
        XCTAssertEqual(DualLayerOverrideMode.allCases.count, 3)
    }
}
