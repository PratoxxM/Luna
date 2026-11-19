import SwiftUI

struct DetailMoreSheetView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    private enum ActionRowID: Hashable {
        case pickSource
        case monitor
        case deleteSeason
        case deleteTitle
    }

    let item: TvItemDetail
    let hasLocalEpisodes: Bool
    var selectedSeasonNumber: Int? = nil
    var canDeleteSelectedSeason: Bool = false
    let onPickSource: () -> Void
    let onToggleMonitor: () -> Void
    var onDeleteSeason: ((Int) -> Void)? = nil
    let onDeleteTitle: () -> Void
    let onClose: () -> Void

    @FocusState private var focusedAction: ActionRowID?
    @Namespace private var moreSheetFocusNamespace

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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mer")
                        .font(LunaTheme.Font.pageTitle)
                        .foregroundStyle(LunaTheme.linen)

                    Text("\(item.title) · \(sessionStore.roomName)")
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.moonlight)
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
                    .focused($focusedAction, equals: .pickSource)
                    .prefersDefaultFocus(true, in: moreSheetFocusNamespace)

                    if shouldShowMonitorButton {
                        DetailMoreActionRowButton(
                            title: monitorTitle,
                            subtitle: monitorSubtitle,
                            systemImage: monitorIcon
                        ) {
                            onToggleMonitor()
                        }
                        .focused($focusedAction, equals: .monitor)
                    }

                    if canDeleteSelectedSeason, let seasonNum = selectedSeasonNumber, let onDeleteSeason {
                        DetailMoreActionRowButton(
                            title: "Slett sesong \(seasonNum)",
                            subtitle: "Frigjør lagringsplass for valgt sesong etter bekreftelse",
                            systemImage: "trash",
                            isDestructive: true
                        ) {
                            onDeleteSeason(seasonNum)
                        }
                        .focused($focusedAction, equals: .deleteSeason)
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
                        .focused($focusedAction, equals: .deleteTitle)
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
            .lunaTopLightEdge(
                cornerRadius: LunaTokens.Radius.panel,
                topColor: LunaTokens.Edge.top3,
                sideColor: LunaTokens.Edge.top1
            )
            .defaultFocus($focusedAction, .pickSource, priority: .userInitiated)
            .focusScope(moreSheetFocusNamespace)
        }
        .onAppear {
            focusedAction = .pickSource
        }
        .onExitCommand {
            onClose()
        }
    }

    private var monitorTitle: String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "Slutt å følge serien" : "Følg serien"
        }
        return item.isMonitoredFlag ? "Avbryt klargjøring" : "Gjør klar på forhånd"
    }

    private var monitorSubtitle: String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "Nye episoder hentes automatisk" : "Nye episoder hentes automatisk når de kommer"
        }
        return item.isMonitoredFlag ? "Lagres på NVMe for umiddelbar start" : "Starter umiddelbart neste gang dere skal se"
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
                    .foregroundStyle(isDestructive ? LunaTheme.coral : (isFocused ? LunaTheme.linen : LunaTheme.moonlight))
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
                    .foregroundStyle(isFocused ? (isDestructive ? LunaTheme.coral : LunaTheme.linen) : LunaTheme.muted)
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

    @FocusState private var focusedChunkIndex: Int?
    @Namespace private var overviewFocusNamespace

    private var focusableParagraphs: [String] {
        Self.makeFocusableChunks(from: overview)
    }

    nonisolated static func makeFocusableChunks(from raw: String) -> [String] {
        let explicit = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        for block in explicit {
            if block.count <= 280 {
                chunks.append(block)
                continue
            }
            var current = ""
            for sentence in block.components(separatedBy: ". ") {
                let piece = sentence.hasSuffix(".") ? sentence : "\(sentence)."
                if current.isEmpty {
                    current = piece
                } else if current.count + piece.count + 1 <= 280 {
                    current += " \(piece)"
                } else {
                    chunks.append(current)
                    current = piece
                }
            }
            if !current.isEmpty {
                if !block.hasSuffix(".") && current.hasSuffix(".") {
                    current.removeLast()
                }
                chunks.append(current)
            }
        }
        return chunks.isEmpty ? [raw] : chunks
    }

    var body: some View {
        let paragraphs = focusableParagraphs

        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(item.title)
                    .font(LunaTheme.Font.heroSerif)
                    .foregroundStyle(LunaTheme.linen)
                    .lineLimit(2)

                Divider().overlay(LunaTheme.warmBorderSubtle)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            OverviewParagraphChunkView(
                                text: paragraph,
                                isFocused: focusedChunkIndex == index,
                                isMultiChunk: paragraphs.count > 1
                            )
                            .focusable(true)
                            .focusEffectDisabled(true)
                            .focused($focusedChunkIndex, equals: index)
                            .prefersDefaultFocus(index == 0, in: overviewFocusNamespace)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
                .frame(maxHeight: 680)
                .defaultFocus($focusedChunkIndex, 0, priority: .userInitiated)
                .focusScope(overviewFocusNamespace)
            }
            .padding(52)
            .frame(maxWidth: 980)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.panel, style: .continuous)
                    .fill(LunaTheme.surface)
            )
            .lunaTopLightEdge(
                cornerRadius: LunaTokens.Radius.panel,
                topColor: LunaTokens.Edge.top3,
                sideColor: LunaTokens.Edge.top1
            )
        }
        .onAppear {
            focusedChunkIndex = 0
        }
        .onExitCommand {
            onClose()
        }
    }
}

private struct OverviewParagraphChunkView: View {
    let text: String
    let isFocused: Bool
    let isMultiChunk: Bool

    var body: some View {
        Text(text)
            .font(LunaTheme.Font.body)
            .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)
            .lineSpacing(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isMultiChunk ? 16 : 0)
            .padding(.vertical, isMultiChunk ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: LunaTokens.Radius.chip, style: .continuous)
                    .fill(isMultiChunk && isFocused ? LunaTheme.surfaceRaised : Color.clear)
            )
    }
}
