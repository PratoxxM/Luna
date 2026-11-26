import SwiftUI

struct DetailMoreSheetView: View {
    enum ActionRowID: Hashable, Sendable {
        case readOverview
        case toggleWatched
        case monitor
        case deleteSeason
        case deleteTitle
    }

    let item: TvItemDetail
    let hasLocalEpisodes: Bool
    var selectedSeasonNumber: Int? = nil
    var canDeleteSelectedSeason: Bool = false
    var canReadOverview: Bool = false
    var watchedActionTitle: String = "Marker som sett"
    let onReadOverview: () -> Void
    let onToggleWatched: () -> Void
    let onToggleMonitor: () -> Void
    var onDeleteSeason: ((Int) -> Void)? = nil
    let onDeleteTitle: () -> Void
    let onClose: () -> Void

    @FocusState private var focusedAction: ActionRowID?
    @Namespace private var moreSheetFocusNamespace

    private var defaultAction: ActionRowID {
        Self.defaultAction(canReadOverview: canReadOverview)
    }

    private var shouldShowMonitorButton: Bool {
        Self.shouldShowMonitorButton(item: item)
    }

    private var shouldShowDeleteButton: Bool {
        Self.shouldShowDeleteButton(item: item, hasLocalEpisodes: hasLocalEpisodes)
    }

    nonisolated static func defaultAction(canReadOverview: Bool) -> ActionRowID {
        canReadOverview ? .readOverview : .toggleWatched
    }

    nonisolated static func shouldShowMonitorButton(item: TvItemDetail) -> Bool {
        if item.mediaType == "series" { return true }
        return item.availability?.isPhysicalLocal != true
    }

    nonisolated static func shouldShowDeleteButton(item: TvItemDetail, hasLocalEpisodes: Bool) -> Bool {
        item.availability?.isPhysicalLocal == true
            || item.availability?.isLocalVfs == true
            || hasLocalEpisodes
            || item.isMonitoredFlag
    }

    nonisolated static func monitorTitle(item: TvItemDetail) -> String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "Slutt å følge serien" : "Følg serien"
        }
        return item.isMonitoredFlag ? "Avbryt klargjøring" : "Gjør klar på forhånd"
    }

    nonisolated static func monitorIcon(item: TvItemDetail) -> String {
        if item.mediaType == "series" {
            return item.isMonitoredFlag ? "bell.fill" : "bell"
        }
        return item.isMonitoredFlag ? "arrow.down.circle.fill" : "arrow.down.circle"
    }

    nonisolated static func deleteTitle(mediaType: String) -> String {
        mediaType == "series" ? "Slett fra samlingen" : "Slett filmen fra samlingen"
    }

    var body: some View {
        LunaSheetContainer(
            title: item.title,
            width: .narrow,
            onClose: onClose
        ) {
            LunaListGroup(showsSurface: false) {
                if canReadOverview {
                    LunaListRow(
                        title: "Les hele handlingen",
                        leadingSystemImage: "text.alignleft",
                        showsChevron: true
                    ) {
                        onReadOverview()
                    }
                    .focused($focusedAction, equals: .readOverview)
                    .prefersDefaultFocus(defaultAction == .readOverview, in: moreSheetFocusNamespace)

                    LunaListDivider()
                }

                LunaListRow(
                    title: watchedActionTitle,
                    leadingSystemImage: item.watched ? "checkmark.circle.fill" : "checkmark",
                    isSelected: item.watched
                ) {
                    onToggleWatched()
                }
                .focused($focusedAction, equals: .toggleWatched)
                .prefersDefaultFocus(defaultAction == .toggleWatched, in: moreSheetFocusNamespace)

                if shouldShowMonitorButton {
                    LunaListDivider()

                    LunaListRow(
                        title: monitorTitle,
                        leadingSystemImage: monitorIcon,
                        isSelected: item.isMonitoredFlag
                    ) {
                        onToggleMonitor()
                    }
                    .focused($focusedAction, equals: .monitor)
                }

                if canDeleteSelectedSeason, let seasonNum = selectedSeasonNumber, let onDeleteSeason {
                    LunaListDivider()

                    LunaListRow(
                        title: "Slett sesong \(seasonNum)",
                        leadingSystemImage: "trash",
                        showsChevron: true,
                        isDestructive: true
                    ) {
                        onDeleteSeason(seasonNum)
                    }
                    .focused($focusedAction, equals: .deleteSeason)
                }

                if shouldShowDeleteButton {
                    LunaListDivider()

                    LunaListRow(
                        title: Self.deleteTitle(mediaType: item.mediaType),
                        leadingSystemImage: "trash",
                        showsChevron: true,
                        isDestructive: true
                    ) {
                        onDeleteTitle()
                    }
                    .focused($focusedAction, equals: .deleteTitle)
                }
            }
            .defaultFocus($focusedAction, defaultAction, priority: .userInitiated)
            .focusScope(moreSheetFocusNamespace)
        }
        .onAppear {
            focusedAction = defaultAction
        }
    }

    private var monitorTitle: String {
        Self.monitorTitle(item: item)
    }

    private var monitorIcon: String {
        Self.monitorIcon(item: item)
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

        LunaSheetContainer(
            title: item.title,
            titleUsesSerif: true,
            width: .narrow,
            maxHeight: 860,
            onClose: onClose
        ) {
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
            .defaultFocus($focusedChunkIndex, 0, priority: .userInitiated)
            .focusScope(overviewFocusNamespace)
        }
        .onAppear {
            focusedChunkIndex = 0
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
