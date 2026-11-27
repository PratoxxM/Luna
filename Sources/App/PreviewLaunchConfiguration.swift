import Foundation

public enum PreviewScreenTarget: String, CaseIterable, Equatable, Sendable {
    case onboarding
    case home
    case homePoster = "home-poster"
    case catalog
    case catalogSeries = "catalog-series"
    case customRow = "custom-row"
    case library
    case search
    case details
    case detailMovie = "detail-movie"
    case detailSourcePicker = "detail-source-picker"
    case detailSeasons = "detail-seasons"
    case detailMore = "detail-more"
    case detailOverview = "detail-overview"
    case detailDelete = "detail-delete"
    case settings
    case settingsSubtitles = "settings-subtitles"
    case settingsPlayback = "settings-playback"
    case settingsAudio = "settings-audio"
    case settingsDiagnostics = "settings-diagnostics"
    case playerCurtain = "player-curtain"
    case playerNerdHud = "player-nerd-hud"
    case playerOsd = "player-osd"
    case playerScrub = "player-scrub"
    case playerSubtitles = "player-subtitles"
    case playerAudio = "player-audio"
    case playerSource = "player-source"
    case playerPicture = "player-picture"
    case playerChapters = "player-chapters"
    case playerSkipIntro = "player-skip-intro"
    case playerNextEpisode = "player-next-episode"
    case playerError = "player-error"

    public static func parse(_ raw: String) -> PreviewScreenTarget? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "onboarding", "pairing", "paring":
            return .onboarding
        case "home", "hjem":
            return .home
        case "home-poster", "home_poster", "homeposter":
            return .homePoster
        case "catalog", "movies", "browse", "filmer":
            return .catalog
        case "catalog-series", "catalog_series", "series", "serier":
            return .catalogSeries
        case "custom-row", "custom_row", "customrow":
            return .customRow
        case "library", "bibliotek":
            return .library
        case "search", "sok", "søk":
            return .search
        case "details", "detail", "detalj", "detaljer":
            return .details
        case "detail-movie", "detail_movie", "movie-detail":
            return .detailMovie
        case "detail-source-picker", "detail_source_picker", "source-picker":
            return .detailSourcePicker
        case "detail-seasons", "detail_seasons", "seasons-sheet":
            return .detailSeasons
        case "detail-more", "detail_more":
            return .detailMore
        case "detail-overview", "detail_overview":
            return .detailOverview
        case "detail-delete", "detail_delete":
            return .detailDelete
        case "settings", "innstillinger":
            return .settings
        case "settings-subtitles", "settings_subtitles":
            return .settingsSubtitles
        case "settings-playback", "settings_playback":
            return .settingsPlayback
        case "settings-audio", "settings_audio", "settings-advanced", "settings_advanced":
            return .settingsAudio
        case "settings-diagnostics", "settings_diagnostics", "settings-system", "settings_system":
            return .settingsDiagnostics
        case "player-curtain", "player_curtain", "curtain":
            return .playerCurtain
        case "player-nerd-hud", "player_nerd_hud", "nerd-hud", "nerdhud":
            return .playerNerdHud
        case "player-osd", "player_osd", "osd":
            return .playerOsd
        case "player-scrub", "player_scrub", "scrub":
            return .playerScrub
        case "player", "playback", "avspiller", "player-subtitles", "player_subtitles":
            return .playerSubtitles
        case "player-audio", "player_audio":
            return .playerAudio
        case "player-source", "player_source":
            return .playerSource
        case "player-picture", "player_picture":
            return .playerPicture
        case "player-chapters", "player_chapters":
            return .playerChapters
        case "player-skip-intro", "player_skip_intro", "skip-intro":
            return .playerSkipIntro
        case "player-next-episode", "player_next_episode", "next-episode":
            return .playerNextEpisode
        case "player-error", "player_error":
            return .playerError
        default:
            return nil
        }
    }

    public var isPlayerScreen: Bool {
        switch self {
        case .playerCurtain, .playerNerdHud, .playerOsd, .playerScrub, .playerSubtitles,
             .playerAudio, .playerSource, .playerPicture, .playerChapters,
             .playerSkipIntro, .playerNextEpisode, .playerError:
            return true
        case .onboarding, .home, .homePoster, .catalog, .catalogSeries, .customRow,
             .library, .search, .details, .detailMovie, .detailSourcePicker,
             .detailSeasons, .detailMore, .detailOverview, .detailDelete,
             .settings, .settingsSubtitles, .settingsPlayback, .settingsAudio, .settingsDiagnostics:
            return false
        }
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

/// Parses `--preview-screen` (`home|home-poster|catalog|catalog-series|library|search|details|detail-movie|detail-source-picker|settings|player-*`)
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
