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
            ("primaryPlayIcon", 24.0),
            ("listRowIcon", 24.0),
            ("microChevron", LunaTokens.Typography.badge),
            ("cardPlaceholderIcon", 36.0),
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
    }
}
