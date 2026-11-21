import SwiftUI

/// Shared release/source row shared cleanly between pre-play `SourcePickerSheetView`
/// and in-player `Kilde` popover (`PlayerQuickPanelView`).
struct SourceCandidateRowView: View {
    let candidate: TvCandidateInfo
    let roomName: String
    let isRecommended: Bool
    let isSelected: Bool
    let activeStatusLabel: String
    let isFocused: Bool
    var dimUnfocusedTitle: Bool = false
    let action: () -> Void

    var body: some View {
        let title = candidate.quickRowTitle(roomName: roomName, isRecommended: isRecommended)
        let baseSubtitle = candidate.quickRowMetadata(activeLabel: isSelected ? activeStatusLabel : nil)
        let subtitle = (candidate.isNorwegian == true) ? "Norsk · \(baseSubtitle)" : baseSubtitle

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
