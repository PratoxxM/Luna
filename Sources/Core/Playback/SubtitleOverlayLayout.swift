import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
public typealias SubtitleLayoutScalar = CGFloat
#else
public typealias SubtitleLayoutScalar = Double
#endif

public struct SubtitleLayoutRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func intersects(_ other: SubtitleLayoutRect) -> Bool {
        x < (other.x + other.width) && (x + width) > other.x &&
            y < (other.y + other.height) && (y + height) > other.y
    }
}

/// Pure subtitle placement rules preventing collisions with bottom OSD (`320 pt`),
/// series continuity overlays (`.skipPrompt` `168 pt`, `.nextEpisodeCard` `300 pt`, or
/// relocated to top when bottom OSD + series card are visible simultaneously), open quick-panel
/// popovers, and `NerdHUDView` (`x = 90..830 pt`, `y = 60..348 pt`).
public enum SubtitleOverlayLayout: Sendable {
    public static let nerdHUDProtectedLayoutRect = SubtitleLayoutRect(x: 90, y: 60, width: 740, height: 288)
    #if canImport(CoreGraphics)
    public static let nerdHUDProtectedRect = CGRect(x: 90, y: 60, width: 740, height: 288)
    #endif
    public static let skipPromptBottomInset: SubtitleLayoutScalar = 168
    public static let nextEpisodeBottomInset: SubtitleLayoutScalar = 300

    public struct VerticalPlacement: Equatable, Sendable {
        public let relocateToTop: Bool
        public let topInset: SubtitleLayoutScalar
        public let bottomInset: SubtitleLayoutScalar
        public let leadingInset: SubtitleLayoutScalar
        public let trailingInset: SubtitleLayoutScalar

        public init(
            relocateToTop: Bool,
            topInset: SubtitleLayoutScalar,
            bottomInset: SubtitleLayoutScalar,
            leadingInset: SubtitleLayoutScalar = 120,
            trailingInset: SubtitleLayoutScalar = 120
        ) {
            self.relocateToTop = relocateToTop
            self.topInset = topInset
            self.bottomInset = bottomInset
            self.leadingInset = leadingInset
            self.trailingInset = trailingInset
        }
    }

    public static func verticalPlacement(
        isBottomBarVisible: Bool,
        isQuickPanelOpen: Bool,
        isNerdHUDVisible: Bool,
        activeSeriesOverlay: ActiveSeriesOverlayKind = .none,
        isScrubbing: Bool = false
    ) -> VerticalPlacement {
        if isQuickPanelOpen || isScrubbing {
            if isNerdHUDVisible {
                return VerticalPlacement(
                    relocateToTop: true,
                    topInset: 72,
                    bottomInset: 0,
                    leadingInset: 856,
                    trailingInset: 90
                )
            }
            return VerticalPlacement(
                relocateToTop: true,
                topInset: 84,
                bottomInset: 0,
                leadingInset: 120,
                trailingInset: 120
            )
        }

        if isBottomBarVisible && activeSeriesOverlay != .none {
            return VerticalPlacement(
                relocateToTop: true,
                topInset: isNerdHUDVisible ? 360 : 84,
                bottomInset: 0,
                leadingInset: 120,
                trailingInset: 120
            )
        }

        let resolvedBottomInset: SubtitleLayoutScalar = {
            if isBottomBarVisible {
                return 320
            }
            switch activeSeriesOverlay {
            case .none:
                return 74
            case .skipPrompt:
                return Self.skipPromptBottomInset
            case .nextEpisodeCard:
                return Self.nextEpisodeBottomInset
            }
        }()

        return VerticalPlacement(
            relocateToTop: false,
            topInset: isNerdHUDVisible ? 360 : 72,
            bottomInset: resolvedBottomInset,
            leadingInset: 120,
            trailingInset: 120
        )
    }
}
