import SwiftUI

public extension LunaTheme {
    /// Standardized 10-foot tvOS typography scale & UI role tokens (`LunaTheme.Font`).
    /// Every tvOS point size sits strictly at or above `22 pt` (`caption2` / `badge` floor).
    enum Font {
        public static let minimumPointSizeFloor: CGFloat = 22.0

        public static let allFixedPointSizes: [(role: String, size: CGFloat)] = [
            ("heroSerif", LunaTokens.Typography.heroSerif),
            ("pageTitle", LunaTokens.Typography.pageTitle),
            ("sectionTitle", LunaTokens.Typography.sectionTitle),
            ("cardTitle", LunaTokens.Typography.cardTitle),
            ("body", LunaTokens.Typography.body),
            ("subtitle", LunaTokens.Typography.subtitle),
            ("caption", LunaTokens.Typography.caption),
            ("badge", LunaTokens.Typography.badge),
            ("brandSerif", 28.0),
            ("heroDisplay", 56.0),
            ("curtainTitle", 46.0),
            ("pairingCode", 88.0),
            ("largeStatusIcon", 52.0),
            ("sheetHeaderIcon", 40.0),
            ("tabIcon", 24.0),
            ("tabTitle", 26.0),
            ("pillIcon", 22.0),
            ("pillLabel", 25.0),
            ("compactPillIcon", 22.0),
            ("compactPillLabel", 23.0),
            ("compactPillBadge", 22.0),
            ("primaryPlayIcon", 24.0),
            ("primaryPlayLabel", 28.0),
            ("tierBadge", 22.0),
            ("cardMicroIcon", 22.0),
            ("cardMicroLabel", 22.0),
            ("posterTitle", 29.0),
            ("posterSubtitle", 24.0),
            ("backdropTitle", LunaTokens.Typography.cardTitle),
            ("backdropSubtitle", LunaTokens.Typography.subtitle),
            ("settingsHeading", LunaTokens.Typography.sectionTitle),
            ("settingsSectionTitle", LunaTokens.Typography.cardTitle),
            ("settingsRowTitle", LunaTokens.Typography.body),
            ("settingsRowSubtitle", LunaTokens.Typography.caption),
            ("settingsRowIcon", 24.0),
            ("settingsMetaTitle", LunaTokens.Typography.subtitle),
            ("settingsMetaValue", LunaTokens.Typography.subtitle),
            ("settingsStatusTag", LunaTokens.Typography.caption),
            ("settingsToggleState", LunaTokens.Typography.caption),
            ("settingsSubLabel", 24.0),
            ("settingsAudioDelay", LunaTokens.Typography.subtitle),
            ("microChevron", LunaTokens.Typography.badge),
            ("cardPlaceholderIcon", 36.0),
        ]

        public static var heroSerif: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.heroSerif,
                weight: .semibold,
                design: .serif
            )
        }
        public static var pageTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.pageTitle,
                weight: .bold
            )
        }
        public static var sectionTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.sectionTitle,
                weight: .semibold
            )
        }
        public static var cardTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.cardTitle,
                weight: .semibold
            )
        }
        public static var body: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.body,
                weight: .regular
            )
        }
        public static var subtitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.subtitle,
                weight: .medium
            )
        }
        public static var caption: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.caption,
                weight: .medium
            )
        }
        public static var badge: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.badge,
                weight: .semibold
            )
        }
        public static var brandSerif: SwiftUI.Font {
            .system(
                size: 28,
                weight: .semibold,
                design: .serif
            )
        }
        public static var heroDisplay: SwiftUI.Font {
            .system(
                size: 56,
                weight: .semibold,
                design: .serif
            )
        }
        public static var curtainTitle: SwiftUI.Font {
            .system(
                size: 46,
                weight: .semibold,
                design: .serif
            )
        }
        public static var pairingCode: SwiftUI.Font {
            .system(
                size: 88,
                weight: .heavy,
                design: .monospaced
            )
        }
        public static var largeStatusIcon: SwiftUI.Font {
            .system(
                size: 52,
                weight: .semibold
            )
        }
        public static var sheetHeaderIcon: SwiftUI.Font {
            .system(
                size: 40,
                weight: .semibold
            )
        }
        public static var tabIcon: SwiftUI.Font {
            .system(
                size: 24,
                weight: .medium
            )
        }
        public static var tabTitle: SwiftUI.Font {
            .system(
                size: 26,
                weight: .semibold
            )
        }
        public static var pillIcon: SwiftUI.Font {
            .system(
                size: 22,
                weight: .semibold
            )
        }
        public static var pillLabel: SwiftUI.Font {
            .system(
                size: 25,
                weight: .medium
            )
        }
        public static var compactPillIcon: SwiftUI.Font {
            .system(
                size: 22,
                weight: .semibold
            )
        }
        public static var compactPillLabel: SwiftUI.Font {
            .system(
                size: 23,
                weight: .medium
            )
        }
        public static var compactPillBadge: SwiftUI.Font {
            .system(
                size: 22,
                weight: .bold
            )
            .monospacedDigit()
        }
        public static var primaryPlayIcon: SwiftUI.Font {
            .system(
                size: 24,
                weight: .bold
            )
        }
        public static var primaryPlayLabel: SwiftUI.Font {
            .system(
                size: 28,
                weight: .semibold
            )
        }
        public static var tierBadge: SwiftUI.Font {
            .system(
                size: 22,
                weight: .bold
            )
        }
        public static var cardMicroIcon: SwiftUI.Font {
            .system(
                size: 22,
                weight: .bold
            )
        }
        public static var cardMicroLabel: SwiftUI.Font {
            .system(
                size: 22,
                weight: .semibold
            )
        }
        public static var posterTitle: SwiftUI.Font {
            .system(
                size: 29,
                weight: .semibold
            )
        }
        public static var posterSubtitle: SwiftUI.Font {
            .system(
                size: 24,
                weight: .medium
            )
        }
        public static var backdropTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.cardTitle,
                weight: .semibold
            )
        }
        public static var backdropSubtitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.subtitle,
                weight: .medium
            )
        }
        public static var settingsHeading: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.sectionTitle,
                weight: .semibold
            )
        }
        public static var settingsSectionTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.cardTitle,
                weight: .semibold
            )
        }
        public static var settingsRowTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.body,
                weight: .medium
            )
        }
        public static var settingsRowSubtitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.caption,
                weight: .regular
            )
        }
        public static var settingsRowIcon: SwiftUI.Font {
            .system(
                size: 24,
                weight: .medium
            )
        }
        public static var settingsMetaTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.subtitle,
                weight: .medium
            )
        }
        public static var settingsMetaValue: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.subtitle,
                weight: .regular
            )
            .monospacedDigit()
        }
        public static var settingsStatusTag: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.caption,
                weight: .semibold
            )
        }
        public static var settingsToggleState: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.caption,
                weight: .bold
            )
        }
        public static var settingsSubLabel: SwiftUI.Font {
            .system(
                size: 24,
                weight: .medium
            )
        }
        public static var settingsAudioDelay: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.subtitle,
                weight: .bold
            )
            .monospacedDigit()
        }
        public static var microChevron: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.badge,
                weight: .bold
            )
        }
        public static var cardPlaceholderIcon: SwiftUI.Font {
            .system(
                size: 36,
                weight: .medium
            )
        }
        public static func subtitleCue(
            size pointSize: CGFloat,
            weight: SwiftUI.Font.Weight = .semibold
        ) -> SwiftUI.Font {
            .system(
                size: max(minimumPointSizeFloor, pointSize),
                weight: weight
            )
        }
    }
}
