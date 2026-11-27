import SwiftUI

/// Shared release/source row shared cleanly between pre-play `SourcePickerSheetView`
/// and in-player `Velg utgave` popover (`PlayerQuickPanelView`).
struct SourceCandidateRowView: View {
    let candidate: TvCandidateInfo
    let isRecommended: Bool
    let isSelected: Bool
    let activeStatusLabel: String
    let isFocused: Bool
    var dimUnfocusedTitle: Bool = false
    var compactForQuickPanel: Bool = false
    let action: () -> Void

    init(
        candidate: TvCandidateInfo,
        isRecommended: Bool,
        isSelected: Bool,
        activeStatusLabel: String,
        isFocused: Bool,
        dimUnfocusedTitle: Bool = false,
        compactForQuickPanel: Bool = false,
        action: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.isRecommended = isRecommended
        self.isSelected = isSelected
        self.activeStatusLabel = activeStatusLabel
        self.isFocused = isFocused
        self.dimUnfocusedTitle = dimUnfocusedTitle
        self.compactForQuickPanel = compactForQuickPanel
        self.action = action
    }

    var body: some View {
        let title = compactForQuickPanel
            ? candidate.inPlayerQuickRowTitle
            : candidate.quickRowTitle(isRecommended: isRecommended)
        let subtitle = candidate.richRowSubtitle(
            isRecommended: isRecommended,
            activeLabel: isSelected ? activeStatusLabel : nil,
            compactForQuickPanel: compactForQuickPanel
        )

        LunaListRow(
            title: title,
            subtitle: subtitle,
            isSelected: isSelected,
            dimUnfocusedTitle: dimUnfocusedTitle,
            externalIsFocused: isFocused,
            action: action
        )
    }
}
