import SwiftUI

struct DetailMoreSheetView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let item: TvItemDetail
    let hasLocalEpisodes: Bool
    let onPickSource: () -> Void
    let onToggleMonitor: () -> Void
    let onDeleteTitle: () -> Void
    let onClose: () -> Void

    private var shouldShowMonitorButton: Bool {
        if item.mediaType == "series" { return true }
        return item.availability?.isPhysicalLocal != true
    }

    private var shouldShowDeleteButton: Bool {
        item.availability?.isPhysicalLocal == true
            || item.availability?.isLocalVfs == true
            || hasLocalEpisodes
            || item.isMonitoredFlag
    }

    var body: some View {
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mer")
                            .font(LunaTheme.Font.pageTitle)
                            .foregroundStyle(LunaTheme.linen)

                        Text("\(item.title) · \(sessionStore.roomName) (\(sessionStore.effectiveEquipmentLabel))")
                            .font(LunaTheme.Font.caption)
                            .foregroundStyle(LunaTheme.moonlight)
                    }

                    Spacer()

                    LunaPillButton("Lukk", systemImage: "xmark", prominence: .subtleChip) {
                        onClose()
                    }
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

                VStack(spacing: 14) {
                    DetailMoreActionRowButton(
                        title: "Velg kilde",
                        subtitle: "Anbefalt for \(sessionStore.roomName): beste bilde og lyd",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        onPickSource()
                    }

                    if shouldShowMonitorButton {
                        DetailMoreActionRowButton(
                            title: monitorTitle,
                            subtitle: monitorSubtitle,
                            systemImage: monitorIcon
                        ) {
                            onToggleMonitor()
                        }
                    }

                    if shouldShowDeleteButton {
                        DetailMoreActionRowButton(
                            title: item.mediaType == "series" ? "Slett fra samlingen" : "Slett filmen fra samlingen",
                            subtitle: "Du får se nøyaktig hva som fjernes før du bekrefter",
                            systemImage: "trash",
                            isDestructive: true
                        ) {
                            onDeleteTitle()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(52)
            .frame(maxWidth: 880)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1.5)
            )
        }
        .onExitCommand {
            onClose()
        }
    }

    private var monitorTitle: String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "Slutt å følge serien" : "Følg serien"
        }
        return item.isMonitoredFlag ? "Avbryt nedlasting" : "Gjør klar på forhånd"
    }

    private var monitorSubtitle: String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "Nye episoder hentes automatisk nå" : "Nye episoder hentes automatisk når de kommer"
        }
        return item.isMonitoredFlag ? "Hentes til rask lokal lagring" : "Starter umiddelbart neste gang dere skal se"
    }

    private var monitorIcon: String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "bell.fill" : "bell"
        }
        return item.isMonitoredFlag ? "arrow.down.circle.fill" : "arrow.down.circle"
    }
}

private struct DetailMoreActionRowButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isDestructive: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(isDestructive ? LunaTheme.coral : (isFocused ? LunaTheme.amber : LunaTheme.moonlight))
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(isDestructive ? LunaTheme.coral : LunaTheme.linen)
                    Text(subtitle)
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(LunaTheme.Font.microChevron)
                    .foregroundStyle(isFocused ? (isDestructive ? LunaTheme.coral : LunaTheme.amber) : LunaTheme.muted)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .fill(isFocused ? LunaTheme.surfaceElevated : LunaTheme.surfaceRaised)
            )
            .lunaFocusSurface(
                .listRow,
                isFocused: isFocused,
                cornerRadius: LunaTheme.cardRadius,
                accentColor: isDestructive ? LunaTheme.coral : LunaTheme.amber
            )
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}

struct DetailOverviewSheetView: View {
    let item: TvItemDetail
    let overview: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(LunaTheme.Font.heroSerif)
                        .foregroundStyle(LunaTheme.linen)
                        .lineLimit(2)

                    Spacer()

                    LunaPillButton("Lukk", systemImage: "xmark", prominence: .subtleChip) {
                        onClose()
                    }
                }

                Divider().overlay(LunaTheme.warmBorderSubtle)

                ScrollView(.vertical, showsIndicators: false) {
                    Text(overview)
                        .font(LunaTheme.Font.body)
                        .foregroundStyle(LunaTheme.moonlight)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 520)

                Spacer(minLength: 0)
            }
            .padding(52)
            .frame(maxWidth: 960)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .strokeBorder(LunaTheme.warmBorderStrong, lineWidth: 1.5)
            )
        }
        .onExitCommand {
            onClose()
        }
    }
}
