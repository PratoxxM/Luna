import SwiftUI

public extension LunaTheme {
    /// Standardized 10-foot tvOS typography scale & UI role tokens (`LunaTheme.Font`).
    /// Contains 9 canonical text roles plus dedicated brand, pill-label & icon roles,
    /// every one strictly at or above `22 pt` (`badge` floor).
    enum Font {
        public static let minimumPointSizeFloor: CGFloat = 22.0

        public static let allFixedPointSizes: [(role: String, size: CGFloat)] = [
            ("heroSerif", LunaTokens.Typography.heroSerif),
            ("titleSerif", LunaTokens.Typography.titleSerif),
            ("pageTitle", LunaTokens.Typography.pageTitle),
            ("sectionTitle", LunaTokens.Typography.sectionTitle),
            ("cardTitle", LunaTokens.Typography.cardTitle),
            ("body", LunaTokens.Typography.body),
            ("subtitle", LunaTokens.Typography.subtitle),
            ("caption", LunaTokens.Typography.caption),
            ("badge", LunaTokens.Typography.badge),
            ("brandSerif", 30.0),
            ("tabTitle", 26.0),
            ("pillLabel", 25.0),
            ("compactPillLabel", 23.0),
            ("primaryPlayLabel", 28.0),
            ("tabIcon", 24.0),
            ("pillIcon", 22.0),
            ("compactPillIcon", 22.0),
            ("primaryPlayIcon", 24.0),
            ("listRowIcon", 24.0),
            ("microChevron", LunaTokens.Typography.badge),
            ("cardPlaceholderIcon", 36.0),
            ("sheetHeaderIcon", 40.0),
            ("largeStatusIcon", 52.0),
            ("pairingCode", 88.0),
        ]

        // MARK: - 9 Canonical Text Roles

        public static var heroSerif: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.heroSerif,
                weight: .semibold,
                design: .serif
            )
        }

        public static var titleSerif: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.titleSerif,
                weight: .semibold,
                design: .serif
            )
        }

        public static var pageTitle: SwiftUI.Font {
            .system(
                size: LunaTokens.Typography.pageTitle,
                weight: .semibold
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

        // MARK: - Brand, Pill Label & Icon Roles

        public static var brandSerif: SwiftUI.Font {
            .system(
                size: 30,
                weight: .semibold,
                design: .serif
            )
        }

        public static var tabTitle: SwiftUI.Font {
            .system(
                size: 26,
                weight: .semibold
            )
        }

        public static var pillLabel: SwiftUI.Font {
            .system(
                size: 25,
                weight: .medium
            )
        }

        public static var compactPillLabel: SwiftUI.Font {
            .system(
                size: 23,
                weight: .medium
            )
        }

        public static var primaryPlayLabel: SwiftUI.Font {
            .system(
                size: 28,
                weight: .semibold
            )
        }

        public static var tabIcon: SwiftUI.Font {
            .system(
                size: 24,
                weight: .medium
            )
        }

        public static var pillIcon: SwiftUI.Font {
            .system(
                size: 22,
                weight: .semibold
            )
        }

        public static var compactPillIcon: SwiftUI.Font {
            .system(
                size: 22,
                weight: .semibold
            )
        }

        public static var primaryPlayIcon: SwiftUI.Font {
            .system(
                size: 24,
                weight: .bold
            )
        }

        public static var listRowIcon: SwiftUI.Font {
            .system(
                size: 24,
                weight: .medium
            )
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

        public static var sheetHeaderIcon: SwiftUI.Font {
            .system(
                size: 40,
                weight: .semibold
            )
        }

        public static var largeStatusIcon: SwiftUI.Font {
            .system(
                size: 52,
                weight: .semibold
            )
        }

        public static var pairingCode: SwiftUI.Font {
            .system(
                size: 88,
                weight: .heavy,
                design: .monospaced
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

        // MARK: - Temporary Deprecated Aliases (Removed in F8)

        @available(*, deprecated, renamed: "heroSerif")
        public static var heroDisplay: SwiftUI.Font { heroSerif }

        @available(*, deprecated, renamed: "heroSerif")
        public static var detailHeroSerif: SwiftUI.Font { heroSerif }

        @available(*, deprecated, renamed: "badge")
        public static var detailKicker: SwiftUI.Font { badge }

        @available(*, deprecated, renamed: "titleSerif")
        public static var curtainTitle: SwiftUI.Font { titleSerif }

        @available(*, deprecated, renamed: "badge")
        public static var compactPillBadge: SwiftUI.Font { badge.monospacedDigit() }

        @available(*, deprecated, renamed: "badge")
        public static var tierBadge: SwiftUI.Font { badge }

        @available(*, deprecated, renamed: "badge")
        public static var cardMicroIcon: SwiftUI.Font { badge }

        @available(*, deprecated, renamed: "badge")
        public static var cardMicroLabel: SwiftUI.Font { badge }

        @available(*, deprecated, renamed: "cardTitle")
        public static var posterTitle: SwiftUI.Font { cardTitle }

        @available(*, deprecated, renamed: "subtitle")
        public static var posterSubtitle: SwiftUI.Font { subtitle }

        @available(*, deprecated, renamed: "cardTitle")
        public static var backdropTitle: SwiftUI.Font { cardTitle }

        @available(*, deprecated, renamed: "subtitle")
        public static var backdropSubtitle: SwiftUI.Font { subtitle }

        @available(*, deprecated, renamed: "sectionTitle")
        public static var settingsHeading: SwiftUI.Font { sectionTitle }

        @available(*, deprecated, renamed: "sectionTitle")
        public static var settingsSectionTitle: SwiftUI.Font { sectionTitle }

        @available(*, deprecated, renamed: "cardTitle")
        public static var settingsRowTitle: SwiftUI.Font { cardTitle }

        @available(*, deprecated, renamed: "subtitle")
        public static var settingsRowSubtitle: SwiftUI.Font { subtitle }

        @available(*, deprecated, renamed: "listRowIcon")
        public static var settingsRowIcon: SwiftUI.Font { listRowIcon }

        @available(*, deprecated, renamed: "subtitle")
        public static var settingsMetaTitle: SwiftUI.Font { subtitle }

        @available(*, deprecated, renamed: "subtitle")
        public static var settingsMetaValue: SwiftUI.Font { subtitle.monospacedDigit() }

        @available(*, deprecated, renamed: "caption")
        public static var settingsStatusTag: SwiftUI.Font { caption }

        @available(*, deprecated, renamed: "caption")
        public static var settingsToggleState: SwiftUI.Font { caption }

        @available(*, deprecated, renamed: "subtitle")
        public static var settingsSubLabel: SwiftUI.Font { subtitle }

        @available(*, deprecated, renamed: "subtitle")
        public static var settingsAudioDelay: SwiftUI.Font { subtitle.monospacedDigit() }
    }
}
