// Generated from design/tokens.json (sha256: 9ba0f8dbf5d792848aad4cbb8b51eed5f2a2366e249e106e1d274718019c4794) — DO NOT EDIT MANUALLY.
// Regenerate via: ./ops/bin/luna-design-tokens --sync

import CoreGraphics
import SwiftUI

public enum LunaTokens {
    public static let tokensSha256 = "9ba0f8dbf5d792848aad4cbb8b51eed5f2a2366e249e106e1d274718019c4794"

    public enum Surface {
        public static let canvas = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0)
        public static let pureBlack = Color(red: 0.0 / 255.0, green: 0.0 / 255.0, blue: 0.0 / 255.0)
        public static let lv1 = Color(red: 20.0 / 255.0, green: 17.0 / 255.0, blue: 15.0 / 255.0)
        public static let subtle = Color(red: 24.0 / 255.0, green: 20.0 / 255.0, blue: 18.0 / 255.0)
        public static let lv2 = Color(red: 30.0 / 255.0, green: 25.0 / 255.0, blue: 22.0 / 255.0)
        public static let lv3 = Color(red: 36.0 / 255.0, green: 30.0 / 255.0, blue: 26.0 / 255.0)
        public static let selected = Color(red: 42.0 / 255.0, green: 35.0 / 255.0, blue: 30.0 / 255.0)
        public static let sheet = Color(red: 20.0 / 255.0, green: 17.0 / 255.0, blue: 15.0 / 255.0)
        public static let glass = Color(red: 18.0 / 255.0, green: 15.0 / 255.0, blue: 13.0 / 255.0).opacity(0.92)
        public static let glassControl = Color(red: 36.0 / 255.0, green: 30.0 / 255.0, blue: 26.0 / 255.0).opacity(0.84)
        public static let glassPill = Color(red: 30.0 / 255.0, green: 25.0 / 255.0, blue: 22.0 / 255.0).opacity(0.84)
        public static let navbar = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.84)
        public static let statePill = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.65)
        public static let badgeScrim = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.75)
        public static let scrim = Color(red: 0.0 / 255.0, green: 0.0 / 255.0, blue: 0.0 / 255.0).opacity(0.65)
        public static let topbarLegacy = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.84)
        public static let stickyLegacy = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.90)
        public static let navLegacy = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.94)
        public static let pillLegacy = Color(red: 24.0 / 255.0, green: 20.0 / 255.0, blue: 18.0 / 255.0).opacity(0.94)
        public static let sheetLegacy = Color(red: 18.0 / 255.0, green: 15.0 / 255.0, blue: 13.0 / 255.0).opacity(0.96)
        public static let sheetHeaderLegacy = Color(red: 18.0 / 255.0, green: 15.0 / 255.0, blue: 13.0 / 255.0).opacity(0.97)
        public static let overlayLegacy = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.78)
        public static let backdropLegacy = Color(red: 0.0 / 255.0, green: 0.0 / 255.0, blue: 0.0 / 255.0).opacity(0.72)
    }

    public enum Edge {
        public static let top1 = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.10)
        public static let top2 = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.14)
        public static let top3 = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.18)
        public static let imageRing = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.12)
        public static let divider = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.10)
        public static let strong = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.18)
        public static let badgeOutline = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.22)
        public static let grabber = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.28)
        public static let progressTrack = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.24)
        public static let miniProgressTrack = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0).opacity(0.16)
        public static let glassHighlight = Color(red: 255.0 / 255.0, green: 236.0 / 255.0, blue: 200.0 / 255.0).opacity(0.10)
        public static let ctaSplitDivider = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0).opacity(0.18)
        public static let ctaPressWash = Color(red: 0.0 / 255.0, green: 0.0 / 255.0, blue: 0.0 / 255.0).opacity(0.10)
        public static let trackLegacy = Color(red: 255.0 / 255.0, green: 255.0 / 255.0, blue: 255.0 / 255.0).opacity(0.14)
    }

    public enum Text {
        public static let primary = Color(red: 245.0 / 255.0, green: 240.0 / 255.0, blue: 232.0 / 255.0)
        public static let secondary = Color(red: 200.0 / 255.0, green: 191.0 / 255.0, blue: 182.0 / 255.0)
        public static let muted = Color(red: 160.0 / 255.0, green: 150.0 / 255.0, blue: 140.0 / 255.0)
        public static let onAccent = Color(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0)
        public static let pauseLine = Color(red: 221.0 / 255.0, green: 214.0 / 255.0, blue: 204.0 / 255.0)
        public static let posterArt = Color(red: 255.0 / 255.0, green: 247.0 / 255.0, blue: 236.0 / 255.0)
        public static let kicker = Color(red: 255.0 / 255.0, green: 240.0 / 255.0, blue: 220.0 / 255.0).opacity(0.82)
    }

    public enum Accent {
        public static let primary = Color(red: 196.0 / 255.0, green: 140.0 / 255.0, blue: 58.0 / 255.0)
        public static let deep = Color(red: 158.0 / 255.0, green: 110.0 / 255.0, blue: 39.0 / 255.0)
        public static let soft = Color(red: 196.0 / 255.0, green: 140.0 / 255.0, blue: 58.0 / 255.0).opacity(0.16)
        public static let border = Color(red: 214.0 / 255.0, green: 170.0 / 255.0, blue: 99.0 / 255.0).opacity(0.45)
        public static let lampPill = Color(red: 196.0 / 255.0, green: 140.0 / 255.0, blue: 58.0 / 255.0).opacity(0.16)
        public static let line = Color(red: 214.0 / 255.0, green: 170.0 / 255.0, blue: 99.0 / 255.0)
        public static let playFocusTop = Color(red: 204.0 / 255.0, green: 150.0 / 255.0, blue: 68.0 / 255.0)
        public static let crescent = Color(red: 196.0 / 255.0, green: 140.0 / 255.0, blue: 58.0 / 255.0)
    }

    public enum Status {
        public static let ok = Color(red: 94.0 / 255.0, green: 191.0 / 255.0, blue: 142.0 / 255.0)
        public static let okBg = Color(red: 94.0 / 255.0, green: 191.0 / 255.0, blue: 142.0 / 255.0).opacity(0.16)
        public static let okBorder = Color(red: 94.0 / 255.0, green: 191.0 / 255.0, blue: 142.0 / 255.0).opacity(0.38)
        public static let warn = Color(red: 224.0 / 255.0, green: 168.0 / 255.0, blue: 75.0 / 255.0)
        public static let warnBg = Color(red: 224.0 / 255.0, green: 168.0 / 255.0, blue: 75.0 / 255.0).opacity(0.16)
        public static let warnBorder = Color(red: 224.0 / 255.0, green: 168.0 / 255.0, blue: 75.0 / 255.0).opacity(0.40)
        public static let danger = Color(red: 217.0 / 255.0, green: 107.0 / 255.0, blue: 82.0 / 255.0)
        public static let dangerBg = Color(red: 217.0 / 255.0, green: 107.0 / 255.0, blue: 82.0 / 255.0).opacity(0.16)
        public static let dangerBorder = Color(red: 217.0 / 255.0, green: 107.0 / 255.0, blue: 82.0 / 255.0).opacity(0.42)
        public static let info = Color(red: 108.0 / 255.0, green: 180.0 / 255.0, blue: 238.0 / 255.0)
        public static let infoBg = Color(red: 108.0 / 255.0, green: 180.0 / 255.0, blue: 238.0 / 255.0).opacity(0.16)
        public static let infoBorder = Color(red: 108.0 / 255.0, green: 180.0 / 255.0, blue: 238.0 / 255.0).opacity(0.38)
    }

    public enum Tier {
        public static let nvme = Color(red: 94.0 / 255.0, green: 191.0 / 255.0, blue: 142.0 / 255.0)
        public static let archive = Color(red: 200.0 / 255.0, green: 191.0 / 255.0, blue: 182.0 / 255.0)
        public static let archiveBg = Color(red: 200.0 / 255.0, green: 191.0 / 255.0, blue: 182.0 / 255.0).opacity(0.14)
        public static let stream = Color(red: 232.0 / 255.0, green: 201.0 / 255.0, blue: 160.0 / 255.0)
    }

    public enum Glow {
        public static let lampStrength: Double = 0.25
        public static let focusUnder: Color = Color(red: 196.0 / 255.0, green: 140.0 / 255.0, blue: 58.0 / 255.0).opacity(0.25)
    }

    public enum Room {
        public static let cinemaLamp = Color(red: 210.0 / 255.0, green: 150.0 / 255.0, blue: 62.0 / 255.0)
        public static let cinemaLampStrength: Double = 0.26
        public static let cinemaTint = Color(red: 42.0 / 255.0, green: 28.0 / 255.0, blue: 16.0 / 255.0)
        public static let cinemaAmbientOpacity: Double = 0.055
        public static let livingLamp = Color(red: 240.0 / 255.0, green: 217.0 / 255.0, blue: 181.0 / 255.0)
        public static let livingLampStrength: Double = 0.22
        public static let livingTint = Color(red: 43.0 / 255.0, green: 36.0 / 255.0, blue: 28.0 / 255.0)
        public static let livingAmbientOpacity: Double = 0.08
    }

    public enum Typography {
        public static let heroSerif: CGFloat = 52.0
        public static let pageTitle: CGFloat = 42.0
        public static let sectionTitle: CGFloat = 34.0
        public static let cardTitle: CGFloat = 30.0
        public static let body: CGFloat = 29.0
        public static let subtitle: CGFloat = 25.0
        public static let caption: CGFloat = 23.0
        public static let badge: CGFloat = 22.0
    }

    public enum Radius {
        public static let chip: CGFloat = 12.0
        public static let poster: CGFloat = 16.0
        public static let card: CGFloat = 18.0
        public static let panel: CGFloat = 24.0
        public static let pill: CGFloat = 999.0
    }

    public enum Layout {
        public static let gutter: CGFloat = 90.0
        public static let posterW: CGFloat = 280.0
        public static let posterH: CGFloat = 420.0
        public static let backdropW: CGFloat = 520.0
        public static let backdropH: CGFloat = 293.0
        public static let cardGap: CGFloat = 40.0
        public static let playBadgeSize: CGFloat = 48.0
        public static let focusBorderWidth: CGFloat = 1.5
        public static let focusBorderOpacity: CGFloat = 0.7
        public static let focusGlowBlur: CGFloat = 30.0
        public static let focusGlowOffsetY: CGFloat = 12.0
        public static let restPosterBrightness: CGFloat = 0.9
    }

    public enum Motion {
        public static let focusSpringResponse: Double = 0.32
        public static let focusSpringDamping: Double = 0.86
        public static let focusFadeSeconds: Double = 0.18
        public static let pressDuration: Double = 0.12
    }
}
