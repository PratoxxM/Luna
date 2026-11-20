import Foundation
#if canImport(Security)
import Security
#endif

/// Sideload-safe persistence namespace.
///
/// ATVLoadly rewrites `CFBundleIdentifier` when signing IPAs with a free Apple ID,
/// so `Luna` NEVER keys `UserDefaults`, Keychain items, or cache paths off the
/// runtime bundle identifier.
public enum SideloadSafeStorage {
    public static let serverURLKey = "luna.v1.server_url"
    public static let deviceIDKey = "luna.v1.device_id"
    public static let deviceNameKey = "luna.v1.device_name"
    public static let roomNameKey = "luna.v1.room_name"
    public static let hardwareProfileKey = "luna.v1.hardware_profile"
    public static let localProfileOverrideKey = "luna.v1.local_profile_override"
    public static let allowSelfSignedLanTLSKey = "luna.v1.allow_lan_tls"

    // Comfort, HDR/OLED subtitle & playback preference keys (sideload-safe)
    public static let hdrSubtitlePresetKey = "luna.v1.comfort.hdr_subtitle_preset"
    public static let subtitleFontScaleKey = "luna.v1.comfort.subtitle_font_scale"
    public static let subtitleBoxOpacityKey = "luna.v1.comfort.subtitle_box_opacity"
    public static let dualLayerOverrideKey = "luna.v1.comfort.dual_layer_override"
    public static let speakerLayoutOverrideKey = "luna.v1.comfort.speaker_layout_override"
    public static let autoPlayNextEpisodeKey = "luna.v1.comfort.auto_play_next_episode"
    public static let smartNordicSubtitleRuleKey = "luna.v1.comfort.smart_nordic_subtitle_rule"
    public static let showNerdHUDKey = "luna.v1.comfort.show_nerd_hud"
    public static let lowResUpscaleModeKey = "luna.v1.comfort.low_res_upscale_mode"
    public static let audioDelayMsKey = "luna.v1.comfort.audio_delay_ms"
    // Retained strictly for "luna.v1.*" legacy UserDefaults migration compatibility.
    public static let showCatCompanionsKey = "luna.v1.comfort.show_cat_companions"
    public static let keepDisplayModeInMenuAfterPlaybackKey = "luna.v1.comfort.keep_display_mode_in_menu"
    public static let didMigrateMenu60HzDefaultV240Key = "luna.v1.comfort.migrated_menu_60hz_v240"
    public static let recentSearchesKey = "luna.v1.recent_searches"
    public static let playerScrubHintCountKey = "luna.v1.player.scrub_hint_count"

    internal static let keychainService = "luna.v1.credentials"
    internal static let tokenAccount = "device_bearer_token"
    internal static let fallbackPrefix = "luna.v1.keychain_fallback."

    public static func ensurePersistentDeviceID(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        if let keychainID = readKeychainString(account: "device_id", defaults: defaults), !keychainID.isEmpty {
            defaults.set(keychainID, forKey: deviceIDKey)
            return keychainID
        }
        let generated = "luna-\(UUID().uuidString.lowercased())"
        defaults.set(generated, forKey: deviceIDKey)
        writeKeychainString(generated, account: "device_id", defaults: defaults)
        return generated
    }

    public static func loadDeviceToken(defaults: UserDefaults = .standard) -> String? {
        readKeychainString(account: tokenAccount, defaults: defaults)
    }

    public static func saveDeviceToken(_ token: String, defaults: UserDefaults = .standard) {
        writeKeychainString(token, account: tokenAccount, defaults: defaults)
    }

    public static func deleteDeviceToken(defaults: UserDefaults = .standard) {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        #endif
        defaults.removeObject(forKey: "\(fallbackPrefix)\(tokenAccount)")
    }

    public nonisolated static func currentAppVersionString(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> String {
        if let ver = infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmed = ver.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "2.7.1"
    }

    public nonisolated static func currentBuildNumberString(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> String? {
        if let build = infoDictionary?["CFBundleVersion"] as? String {
            let trimmed = build.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let num = infoDictionary?["CFBundleVersion"] as? Int, num > 0 {
            return String(num)
        }
        return nil
    }

    public nonisolated static func currentAppVersionDisplayString(
        infoDictionary: [String: Any]? = Bundle.main.infoDictionary
    ) -> String {
        let version = currentAppVersionString(infoDictionary: infoDictionary)
        if let build = currentBuildNumberString(infoDictionary: infoDictionary) {
            return "\(version) (bygg \(build))"
        }
        return version
    }

    private static func readKeychainString(account: String, defaults: UserDefaults) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            return text
        }
        #endif
        if let fallback = defaults.string(forKey: "\(fallbackPrefix)\(account)"), !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    private static func writeKeychainString(_ value: String, account: String, defaults: UserDefaults) {
        #if canImport(Security)
        let encoded = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var insert = baseQuery
        insert[kSecValueData as String] = encoded
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecSuccess {
            defaults.removeObject(forKey: "\(fallbackPrefix)\(account)")
        } else {
            // Preserve pairing across sideload profiles if securityd rejects Keychain write (e.g. -34018)
            defaults.set(value, forKey: "\(fallbackPrefix)\(account)")
        }
        #else
        defaults.set(value, forKey: "\(fallbackPrefix)\(account)")
        #endif
    }
}
