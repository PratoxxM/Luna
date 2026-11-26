import SwiftUI

/// Focus-isolated catalog filter & genre bar (`F-10`):
/// - Fixed left zone keeps sort trigger (`arrow.up.arrow.down`), `Lokalt`, and `Skjul sette`
///   permanently visible at `x = 90`.
/// - Right zone scrolls genre pills horizontally behind a `56 pt` trailing alpha fade mask
///   so genre chips never clip harshly against the screen edge.
struct CatalogFilterBarView: View {
    nonisolated static let trailingMaskFadeWidth: CGFloat = 56

    @Environment(\.lunaSubpageVisibility) private var subpageVisibility

    let categoryTitle: String
    let availableGenres: [TvGenreChip]
    @Binding var selectedSort: String
    @Binding var localOnly: Bool
    @Binding var unwatchedOnly: Bool
    @Binding var selectedGenreSlug: String?
    @Binding var selectedGenreLabel: String?
    let entryFocusNonce: Int
    let isEntryActive: Bool
    let onScrollToTop: @MainActor () -> Void
    let onMoveDown: @MainActor () -> Void

    @State private var showSortSheet: Bool = false
    @State private var sortModalToken = UUID()
    @FocusState private var focusedFilterId: String?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                LunaPillButton(
                    CatalogSortOption.label(for: selectedSort),
                    systemImage: "arrow.up.arrow.down",
                    isSelected: true,
                    prominence: .glassPill,
                    size: .compact
                ) {
                    showSortSheet = true
                }
                .focused($focusedFilterId, equals: "sort-trigger")

                LunaPillButton(
                    "Lokalt",
                    systemImage: localOnly ? "checkmark" : nil,
                    isSelected: localOnly,
                    prominence: .glassPill,
                    size: .compact
                ) {
                    localOnly.toggle()
                }
                .focused($focusedFilterId, equals: "local-only")

                LunaPillButton(
                    "Skjul sette",
                    systemImage: unwatchedOnly ? "checkmark" : nil,
                    isSelected: unwatchedOnly,
                    prominence: .glassPill,
                    size: .compact
                ) {
                    unwatchedOnly.toggle()
                }
                .focused($focusedFilterId, equals: "unwatched")
            }
            .fixedSize(horizontal: true, vertical: false)

            if !availableGenres.isEmpty {
                Rectangle()
                    .fill(LunaTheme.warmBorderStrong)
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        LunaPillButton(
                            "Alle sjangre",
                            isSelected: selectedGenreSlug == nil,
                            prominence: .glassPill,
                            size: .compact
                        ) {
                            selectedGenreSlug = nil
                            selectedGenreLabel = nil
                        }
                        .focused($focusedFilterId, equals: "genre-all")

                        ForEach(availableGenres) { chip in
                            let active = selectedGenreSlug == chip.slug
                            LunaPillButton(
                                chip.label,
                                isSelected: active,
                                prominence: .glassPill,
                                size: .compact
                            ) {
                                if active {
                                    selectedGenreSlug = nil
                                    selectedGenreLabel = nil
                                } else {
                                    selectedGenreSlug = chip.slug
                                    selectedGenreLabel = chip.label
                                }
                            }
                            .focused($focusedFilterId, equals: "genre-\(chip.slug)")
                        }
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentMargins(.zero, for: .scrollContent)
                .mask {
                    HStack(spacing: 0) {
                        LunaTheme.pureBlack
                        LinearGradient(
                            colors: [LunaTheme.pureBlack, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: Self.trailingMaskFadeWidth)
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, LunaTheme.horizontalGutter)
        .padding(.vertical, availableGenres.isEmpty ? 10 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .lunaEntryFocusTarget(
            nonce: entryFocusNonce,
            isActive: isEntryActive,
            focus: $focusedFilterId,
            target: { "sort-trigger" },
            onTrigger: onScrollToTop
        )
        .onMoveCommand { direction in
            if direction == .down {
                onMoveDown()
            }
        }
        .sheet(isPresented: $showSortSheet, onDismiss: {
            restoreFocusToSortTrigger()
        }) {
            CatalogSortPickerSheetView(
                categoryTitle: categoryTitle,
                selectedSort: selectedSort,
                onSelectSort: { nextSort in
                    showSortSheet = false
                    if selectedSort != nextSort {
                        selectedSort = nextSort
                    }
                },
                onClose: {
                    showSortSheet = false
                }
            )
            .preferredColorScheme(.dark)
        }
        .onChange(of: showSortSheet) { _, isPresented in
            if isPresented {
                subpageVisibility.enterModal(sortModalToken)
            } else {
                subpageVisibility.leaveModal(sortModalToken)
            }
        }
        .onDisappear {
            subpageVisibility.leaveModal(sortModalToken)
        }
    }

    private func restoreFocusToSortTrigger() {
        focusedFilterId = "sort-trigger"
        Task { @MainActor in
            await Task.yield()
            if focusedFilterId == nil {
                focusedFilterId = "sort-trigger"
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
            if !Task.isCancelled, !showSortSheet, focusedFilterId == nil {
                focusedFilterId = "sort-trigger"
            }
        }
    }
}

private struct CatalogSortPickerSheetView: View {
    let categoryTitle: String
    let selectedSort: String
    let onSelectSort: (String) -> Void
    let onClose: () -> Void

    @FocusState private var focusedSortID: String?
    @Namespace private var sortSheetNamespace

    var body: some View {
        LunaSheetContainer(
            title: "Sortering",
            subtitle: categoryTitle,
            width: .narrow,
            maxHeight: 680,
            onClose: onClose
        ) {
            LunaListGroup(showsSurface: false) {
                let options = CatalogSortOption.allOptions
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    let isSelected = option.id == selectedSort
                    LunaListRow(
                        title: option.label,
                        subtitle: option.subtitle,
                        isSelected: isSelected,
                        externalIsFocused: focusedSortID == option.id
                    ) {
                        onSelectSort(option.id)
                    }
                    .focused($focusedSortID, equals: option.id)
                    .prefersDefaultFocus(isSelected, in: sortSheetNamespace)

                    if index < options.count - 1 {
                        LunaListDivider()
                    }
                }
            }
            .padding(.vertical, 4)
            .defaultFocus($focusedSortID, selectedSort, priority: .userInitiated)
            .focusScope(sortSheetNamespace)
            .onAppear {
                focusedSortID = selectedSort
            }
        }
    }
}
