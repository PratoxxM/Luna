import Foundation
import XCTest
@testable import Luna

final class SideloadSafeStorageTests: XCTestCase {
    func testSideloadSafeStorageKeysPreserveLunaV1Namespace() {
        let allKeys = [
            SideloadSafeStorage.serverURLKey,
            SideloadSafeStorage.serverLocalHostnameURLKey,
            SideloadSafeStorage.fallbackServerURLKey,
            SideloadSafeStorage.deviceIDKey,
            SideloadSafeStorage.deviceNameKey,
            SideloadSafeStorage.roomNameKey,
            SideloadSafeStorage.hardwareProfileKey,
            SideloadSafeStorage.allowSelfSignedLanTLSKey,
            SideloadSafeStorage.hdrSubtitlePresetKey,
            SideloadSafeStorage.subtitleFontScaleKey,
            SideloadSafeStorage.subtitleBoxOpacityKey,
            SideloadSafeStorage.dualLayerOverrideKey,
            SideloadSafeStorage.speakerLayoutOverrideKey,
            SideloadSafeStorage.autoPlayNextEpisodeKey,
            SideloadSafeStorage.smartNordicSubtitleRuleKey,
            SideloadSafeStorage.recognizesBitmapSubtitleTextKey,
            SideloadSafeStorage.showNerdHUDKey,
            SideloadSafeStorage.lowResUpscaleModeKey,
            SideloadSafeStorage.fullHDUpscaleEnabledKey,
            SideloadSafeStorage.audioDelayMsKey,
            SideloadSafeStorage.audioEnhancementModeKey,
            SideloadSafeStorage.menuDisplayModeKey,
            SideloadSafeStorage.recentSearchesKey,
            SideloadSafeStorage.preferNorwegianAudioPrefix,
            SideloadSafeStorage.candidateSubtitleDelayPrefix,
        ]

        XCTAssertEqual(allKeys.count, 25)
        XCTAssertEqual(Set(allKeys).count, allKeys.count, "All persistence keys must be unique")
        for key in allKeys {
            XCTAssertTrue(key.hasPrefix("luna.v1."), "Key \(key) must keep luna.v1. namespace")
            XCTAssertFalse(key.contains("local.lunacore"), "Key \(key) must never embed a bundle identifier prefix")
            XCTAssertFalse(key.contains("lunacore.luna"), "Key \(key) must never embed a bundle identifier prefix")
        }

        XCTAssertEqual(SideloadSafeStorage.serverURLKey, "luna.v1.server_url")
        XCTAssertEqual(SideloadSafeStorage.serverLocalHostnameURLKey, "luna.v1.server_local_hostname_url")
        XCTAssertEqual(SideloadSafeStorage.fallbackServerURLKey, "luna.v1.fallback_server_url")
        XCTAssertEqual(SideloadSafeStorage.deviceIDKey, "luna.v1.device_id")
        XCTAssertEqual(SideloadSafeStorage.deviceNameKey, "luna.v1.device_name")
        XCTAssertEqual(SideloadSafeStorage.roomNameKey, "luna.v1.room_name")
        XCTAssertEqual(SideloadSafeStorage.hardwareProfileKey, "luna.v1.hardware_profile")
        XCTAssertEqual(SideloadSafeStorage.allowSelfSignedLanTLSKey, "luna.v1.allow_lan_tls")
        XCTAssertEqual(SideloadSafeStorage.hdrSubtitlePresetKey, "luna.v1.comfort.hdr_subtitle_preset")
        XCTAssertEqual(SideloadSafeStorage.subtitleFontScaleKey, "luna.v1.comfort.subtitle_font_scale")
        XCTAssertEqual(SideloadSafeStorage.subtitleBoxOpacityKey, "luna.v1.comfort.subtitle_box_opacity")
        XCTAssertEqual(SideloadSafeStorage.dualLayerOverrideKey, "luna.v1.comfort.dual_layer_override")
        XCTAssertEqual(SideloadSafeStorage.speakerLayoutOverrideKey, "luna.v1.comfort.speaker_layout_override")
        XCTAssertEqual(SideloadSafeStorage.autoPlayNextEpisodeKey, "luna.v1.comfort.auto_play_next_episode")
        XCTAssertEqual(SideloadSafeStorage.smartNordicSubtitleRuleKey, "luna.v1.comfort.smart_nordic_subtitle_rule")
        XCTAssertEqual(SideloadSafeStorage.recognizesBitmapSubtitleTextKey, "luna.v1.comfort.recognizes_bitmap_subtitle_text")
        XCTAssertEqual(SideloadSafeStorage.showNerdHUDKey, "luna.v1.comfort.show_nerd_hud")
        XCTAssertEqual(SideloadSafeStorage.lowResUpscaleModeKey, "luna.v1.comfort.low_res_upscale_mode")
        XCTAssertEqual(SideloadSafeStorage.fullHDUpscaleEnabledKey, "luna.v1.comfort.upscale_full_hd_video")
        XCTAssertEqual(SideloadSafeStorage.audioDelayMsKey, "luna.v1.comfort.audio_delay_ms")
        XCTAssertEqual(SideloadSafeStorage.audioEnhancementModeKey, "luna.v1.comfort.audio_enhancement_mode")
        XCTAssertEqual(SideloadSafeStorage.menuDisplayModeKey, "luna.v1.comfort.menu_display_mode")
        XCTAssertEqual(SideloadSafeStorage.recentSearchesKey, "luna.v1.recent_searches")
        XCTAssertEqual(SideloadSafeStorage.preferNorwegianAudioPrefix, "luna.v1.playback.norwegian_audio.")
        XCTAssertEqual(SideloadSafeStorage.candidateSubtitleDelayPrefix, "luna.v1.playback.subtitle_delay.")
        XCTAssertEqual(SideloadSafeStorage.keychainService, "luna.v1.credentials")
        XCTAssertEqual(SideloadSafeStorage.tokenAccount, "device_bearer_token")
        XCTAssertEqual(SideloadSafeStorage.fallbackPrefix, "luna.v1.keychain_fallback.")
    }

    func testPersistentDeviceIDAndTokenRoundtripWithIsolatedDefaults() {
        let suite = "luna.test.sideload.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        let previousToken = SideloadSafeStorage.loadDeviceToken(defaults: defaults)
        defer {
            if let previousToken {
                SideloadSafeStorage.saveDeviceToken(previousToken, defaults: defaults)
            } else {
                SideloadSafeStorage.deleteDeviceToken(defaults: defaults)
            }
            defaults.removePersistentDomain(forName: suite)
        }

        let firstID = SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaults)
        XCTAssertTrue(firstID.hasPrefix("luna-"))
        XCTAssertEqual(defaults.string(forKey: SideloadSafeStorage.deviceIDKey), firstID)

        let secondID = SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaults)
        XCTAssertEqual(firstID, secondID)

        // Pre-populated defaults ID is always honored first (survives bundle ID changes).
        let customID = "luna-custom-\(UUID().uuidString.lowercased())"
        defaults.set(customID, forKey: SideloadSafeStorage.deviceIDKey)
        XCTAssertEqual(SideloadSafeStorage.ensurePersistentDeviceID(defaults: defaults), customID)

        let sampleToken = "tok_\(UUID().uuidString)"
        SideloadSafeStorage.saveDeviceToken(sampleToken, defaults: defaults)
        XCTAssertEqual(SideloadSafeStorage.loadDeviceToken(defaults: defaults), sampleToken)

        SideloadSafeStorage.deleteDeviceToken(defaults: defaults)
        XCTAssertNil(SideloadSafeStorage.loadDeviceToken(defaults: defaults))
    }
}
