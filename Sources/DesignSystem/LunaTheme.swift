import SwiftUI

/// Subtle room calibration character (`C6+`) modulating only static menu glow and card lamp tint,
/// never touching full-screen HDR/Dolby Vision video surfaces.
public enum LunaRoomAtmosphere: String, CaseIterable, Equatable, Sendable {
    case cinema
    case living
    case neutral

    public nonisolated static func resolve(
        atmosphere: String?,
        hardwareProfile: String,
        roomName: String
    ) -> LunaRoomAtmosphere {
        let explicit = (atmosphere ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if explicit == "living" || explicit == "stua" { return .living }
        if explicit == "cinema" || explicit == "kjellerstua" { return .cinema }
        if explicit == "neutral" { return .neutral }

        let prof = hardwareProfile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if prof == "hdr10-512" || prof == "living" || prof == "livingroom" {
            return .living
        }
        if prof == "dv-fel-714" || prof == "cinema" {
            return .cinema
        }

        let room = roomName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if room.contains("stua") && !room.contains("kjeller") { return .living }
        if room.contains("kjeller") || room.contains("kino") { return .cinema }
        return .neutral
    }

    public var lampColor: Color {
        switch self {
        case .cinema: return LunaTokens.Room.cinemaLamp
        case .living: return LunaTokens.Room.livingLamp
        case .neutral: return LunaTheme.amber
        }
    }

    public var lampStrength: Double {
        switch self {
        case .cinema: return LunaTokens.Room.cinemaLampStrength
        case .living: return LunaTokens.Room.livingLampStrength
        case .neutral: return LunaTokens.Glow.lampStrength
        }
    }

    public var ambientOpacity: Double {
        switch self {
        case .cinema: return LunaTokens.Room.cinemaAmbientOpacity
        case .living: return LunaTokens.Room.livingAmbientOpacity
        case .neutral: return (LunaTokens.Room.cinemaAmbientOpacity + LunaTokens.Room.livingAmbientOpacity) * 0.5
        }
    }
}

private struct LunaRoomAtmosphereKey: EnvironmentKey {
    static let defaultValue: LunaRoomAtmosphere = .cinema
}

public extension EnvironmentValues {
    var lunaRoomAtmosphere: LunaRoomAtmosphere {
        get { self[LunaRoomAtmosphereKey.self] }
        set { self[LunaRoomAtmosphereKey.self] = newValue }
    }
}

public enum LunaTheme {
    /// Near-black warm charcoal menu base (`#0A0908`) — protects LG OLED black floor with zero cold blue cast.
    public static let canvas = LunaTokens.Surface.canvas
    /// Pure black (`#000000`) reserved for OLED video surface & startup curtain.
    public static let pureBlack = LunaTokens.Surface.pureBlack
    /// Calm matte espresso surface (`#14110F`) for cards, panels, and shelves.
    public static let surface = LunaTokens.Surface.lv1
    /// Elevated matte espresso (`#1E1916`) for resting secondary buttons & grouped Settings rows.
    public static let surfaceRaised = LunaTokens.Surface.lv2
    /// Warm roasted espresso (`#2A231E`) for active/selected secondary controls without competing with «Spill av».
    public static let surfaceSelected = LunaTokens.Surface.selected
    /// Elevated roasted espresso (`#241E1A`) for focused secondary controls, wide settings, drawer, and source-picker rows.
    public static let surfaceElevated = LunaTokens.Surface.lv3
    /// Dark HDR/Dolby Vision-safe warm cinema glass (`#120F0D` @ 92%) — avoids cold tvOS system blur 203-nit washout.
    public static let cinemaGlass = LunaTokens.Surface.glass

    /// Warm linen (`#F5F0E8`) for crisp, non-glaring primary titles & headings.
    public static let linen = LunaTokens.Text.primary
    /// Warm parchment (`#C8BFB6`) for secondary labels and resting button copy.
    public static let moonlight = LunaTokens.Text.secondary
    /// Daylight-calibrated warm taupe (`#A0968C`) — readable in bright rooms (Frame Pro) while gentle in dark OLED rooms.
    public static let muted = LunaTokens.Text.muted
    /// Non-glaring warm-white cinema pause timeline fill (`#DDD6CC`).
    public static let pauseWarmLine = LunaTokens.Text.pauseLine

    /// Muted antique bronze-brass (`#C48C3A`) — primary accent reserved for Siri Remote focus & «Spill av» (`6.78:1` vs `#0A0908`).
    public static let amber = LunaTokens.Accent.primary
    /// Deeper warm bronze (`#9E6E27`) for subtle primary gradient depth.
    public static let amberDeep = LunaTokens.Accent.deep
    /// Calm sage-emerald (`#5EBF8E`) reserved for healthy status, NVMe badges & Sett checkmarks.
    public static let emerald = LunaTokens.Status.ok
    public static let statusOk = LunaTokens.Status.ok
    /// Dedicated warm ochre warning (`#E0A84B`) — distinct from focus bronze so warnings never reuse focus gold.
    public static let warn = LunaTokens.Status.warn
    /// Warm terracotta (`#D96B52`) reserved for destructive/error actions & alerts.
    public static let coral = LunaTokens.Status.danger
    public static let danger = LunaTokens.Status.danger

    /// Storage tier colors shared across iPhone & tvOS.
    public static let tierNvme = LunaTokens.Tier.nvme
    public static let tierArchive = LunaTokens.Tier.archive

    /// Base warm cream border tint (`#FFF4E6`) used at 10–18% opacity for 1 pt matte hairlines.
    public static let warmBorderBase = Color(red: 255.0 / 255.0, green: 244.0 / 255.0, blue: 230.0 / 255.0)
    public static let warmBorderSubtle = LunaTokens.Edge.top1
    public static let warmBorder = LunaTokens.Edge.top2
    public static let warmBorderStrong = LunaTokens.Edge.top3

    /// Calm antique bronze Siri Remote focus fill (`#C48C3A -> #9E6E27`) reserved for primary actions.
    public static let focusGoldTop = amber
    public static let focusGoldBorder = LunaTokens.Accent.line
    /// Subtle warm bronze highlight reserved for focused `PrimaryPlayButton` («Spill av»).
    public static let playFocusTop = LunaTokens.Accent.playFocusTop

    public static let horizontalGutter: CGFloat = LunaTokens.Layout.gutter
    public static let posterRadius: CGFloat = LunaTokens.Radius.poster
    public static let cardRadius: CGFloat = LunaTokens.Radius.card
    public static let posterGridColumns: [GridItem] = Array(
        repeating: GridItem(.fixed(LunaTokens.Layout.gridPosterW), spacing: LunaTokens.Layout.gridCardGap, alignment: .topLeading),
        count: 6
    )

    public static var playFocusGradient: LinearGradient {
        LinearGradient(
            colors: [playFocusTop, amber, amberDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var primaryAmberGradient: LinearGradient {
        LinearGradient(
            colors: [amber, amberDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static func topLightEdgeGradient(
        topColor: Color = LunaTokens.Edge.top2,
        sideColor: Color = .clear
    ) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: topColor, location: 0.0),
                .init(color: topColor.opacity(0.32), location: 0.14),
                .init(color: sideColor, location: 0.42),
                .init(color: sideColor, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static func cardTitleColor(isFocused: Bool) -> Color {
        linen
    }

    public static func cardSubtitleColor(isFocused: Bool) -> Color {
        isFocused ? moonlight : muted
    }

    public static func color(fromHex rawHex: String?) -> Color? {
        guard var cleaned = rawHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else {
            return nil
        }
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

public extension View {
    /// True 1 pt overhead lamp highlight along the top edge (`Edge.top2` fading downward),
    /// giving OLED surfaces physical depth without cold black drop shadows.
    func lunaTopLightEdge(
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        topColor: Color = LunaTokens.Edge.top2,
        sideColor: Color = .clear,
        lineWidth: CGFloat = 1.0
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LunaTheme.topLightEdgeGradient(topColor: topColor, sideColor: sideColor),
                    lineWidth: lineWidth
                )
                .allowsHitTesting(false)
        )
    }
}
