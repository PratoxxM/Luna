import SwiftUI

public extension LunaTheme {
    /// Standardized 10-foot tvOS typography scale & UI role tokens (`LunaTheme.Font`).
    enum Font {
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
                size: 26,
                weight: .semibold,
                design: .serif
            )
        }
        public static var heroDisplay: SwiftUI.Font {
            .system(
                size: 56,
                weight: .bold,
                design: .rounded
            )
        }
        public static var curtainTitle: SwiftUI.Font {
            .system(
                size: 46,
                weight: .bold,
                design: .rounded
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
                size: 20,
                weight: .medium
            )
        }
        public static var tabTitle: SwiftUI.Font {
            .system(
                size: 22,
                weight: .semibold
            )
        }
        public static var pillIcon: SwiftUI.Font {
            .system(
                size: 17,
                weight: .semibold
            )
        }
        public static var pillLabel: SwiftUI.Font {
            .system(
                size: 19,
                weight: .medium
            )
        }
        public static var compactPillIcon: SwiftUI.Font {
            .system(
                size: 15,
                weight: .semibold
            )
        }
        public static var compactPillLabel: SwiftUI.Font {
            .system(
                size: 17,
                weight: .medium
            )
        }
        public static var compactPillBadge: SwiftUI.Font {
            .system(
                size: 14,
                weight: .bold
            )
            .monospacedDigit()
        }
        public static var primaryPlayIcon: SwiftUI.Font {
            .system(
                size: 20,
                weight: .bold
            )
        }
        public static var primaryPlayLabel: SwiftUI.Font {
            .system(
                size: 23,
                weight: .semibold
            )
        }
        public static var tierBadge: SwiftUI.Font {
            .system(
                size: 14,
                weight: .bold
            )
        }
        public static var cardMicroIcon: SwiftUI.Font {
            .system(
                size: 16,
                weight: .bold
            )
        }
        public static var cardMicroLabel: SwiftUI.Font {
            .system(
                size: 18,
                weight: .bold
            )
        }
        public static var posterTitle: SwiftUI.Font {
            .system(
                size: 26,
                weight: .semibold
            )
        }
        public static var posterSubtitle: SwiftUI.Font {
            .system(
                size: 22,
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
                size: LunaTokens.Typography.caption,
                weight: .medium
            )
        }
        public static var settingsHeading: SwiftUI.Font {
            .system(
                size: 24,
                weight: .semibold
            )
        }
        public static var settingsSectionTitle: SwiftUI.Font {
            .system(
                size: 22,
                weight: .semibold
            )
        }
        public static var settingsRowTitle: SwiftUI.Font {
            .system(
                size: 19,
                weight: .medium
            )
        }
        public static var settingsRowSubtitle: SwiftUI.Font {
            .system(
                size: 15,
                weight: .regular
            )
        }
        public static var settingsRowIcon: SwiftUI.Font {
            .system(
                size: 17,
                weight: .medium
            )
        }
        public static var settingsMetaTitle: SwiftUI.Font {
            .system(
                size: 17,
                weight: .medium
            )
        }
        public static var settingsMetaValue: SwiftUI.Font {
            .system(
                size: 17,
                weight: .regular
            )
            .monospacedDigit()
        }
        public static var settingsStatusTag: SwiftUI.Font {
            .system(
                size: 16,
                weight: .semibold
            )
        }
        public static var settingsToggleState: SwiftUI.Font {
            .system(
                size: 15,
                weight: .bold
            )
        }
        public static var settingsSubLabel: SwiftUI.Font {
            .system(
                size: 16,
                weight: .medium
            )
        }
        public static var settingsAudioDelay: SwiftUI.Font {
            .system(
                size: 17,
                weight: .bold
            )
            .monospacedDigit()
        }
        public static var microChevron: SwiftUI.Font {
            .system(
                size: 13,
                weight: .bold
            )
        }
        public static func subtitleCue(size pointSize: CGFloat) -> SwiftUI.Font {
            .system(
                size: pointSize,
                weight: .semibold,
                design: .rounded
            )
        }
    }
}
