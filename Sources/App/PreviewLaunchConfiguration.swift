import Foundation

public enum PreviewScreenTarget: String, CaseIterable, Equatable, Sendable {
    case home
    case homePoster = "home-poster"
    case catalog
    case library
    case details
    case settings
    case playerAudio = "player-audio"
    case playerSource = "player-source"

    public static func parse(_ raw: String) -> PreviewScreenTarget? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "home", "hjem":
            return .home
        case "home-poster", "home_poster", "homeposter":
            return .homePoster
        case "catalog", "movies", "browse", "filmer":
            return .catalog
        case "library", "bibliotek":
            return .library
        case "details", "detail", "detalj", "detaljer":
            return .details
        case "settings", "innstillinger":
            return .settings
        case "player", "playback", "avspiller", "player-audio", "player_audio":
            return .playerAudio
        case "player-source", "player_source":
            return .playerSource
        default:
            return nil
        }
    }

    public var isPlayerScreen: Bool {
        self == .playerAudio || self == .playerSource
    }

    public var isHomeScreen: Bool {
        self == .home || self == .homePoster
    }
}

public enum PreviewFocusDirection: String, CaseIterable, Equatable, Sendable {
    case up
    case down
    case left
    case right
    case select

    public static func parse(_ raw: String) -> PreviewFocusDirection? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "up":
            return .up
        case "down":
            return .down
        case "left":
            return .left
        case "right":
            return .right
        case "select", "enter":
            return .select
        default:
            return nil
        }
    }
}

/// Parses `--preview-screen <home|home-poster|catalog|library|details|settings|player-audio|player-source>`
/// and optional `--preview-focus <up|down|left|right|select>` launch arguments for deterministic
/// tvOS Simulator visual verification without live network dependencies.
public struct PreviewLaunchConfiguration: Equatable, Sendable {
    public let screen: PreviewScreenTarget
    public let focusDirection: PreviewFocusDirection?

    public init(screen: PreviewScreenTarget, focusDirection: PreviewFocusDirection? = nil) {
        self.screen = screen
        self.focusDirection = focusDirection
    }

    public static let current: PreviewLaunchConfiguration? = parse(arguments: ProcessInfo.processInfo.arguments)

    public static func parse(arguments: [String]) -> PreviewLaunchConfiguration? {
        var parsedScreen: PreviewScreenTarget?
        var parsedFocus: PreviewFocusDirection?

        var idx = 0
        while idx < arguments.count {
            let arg = arguments[idx]
            if arg == "--preview-screen", idx + 1 < arguments.count {
                parsedScreen = PreviewScreenTarget.parse(arguments[idx + 1])
                idx += 2
                continue
            }
            if arg.hasPrefix("--preview-screen=") {
                let value = String(arg.dropFirst("--preview-screen=".count))
                parsedScreen = PreviewScreenTarget.parse(value)
                idx += 1
                continue
            }
            if arg == "--preview-focus", idx + 1 < arguments.count {
                parsedFocus = PreviewFocusDirection.parse(arguments[idx + 1])
                idx += 2
                continue
            }
            if arg.hasPrefix("--preview-focus=") {
                let value = String(arg.dropFirst("--preview-focus=".count))
                parsedFocus = PreviewFocusDirection.parse(value)
                idx += 1
                continue
            }
            idx += 1
        }

        guard let screen = parsedScreen else {
            return nil
        }
        return PreviewLaunchConfiguration(screen: screen, focusDirection: parsedFocus)
    }
}
