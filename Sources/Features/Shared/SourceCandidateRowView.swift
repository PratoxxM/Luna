import SwiftUI

/// Shared release/source row shared cleanly between pre-play `SourcePickerSheetView`
/// and in-player `Velg utgave` popover (`PlayerQuickPanelView`).
struct SourceCandidateRowView: View {
    let candidate: TvCandidateInfo
    let roomName: String
    let isRecommended: Bool
    let isSelected: Bool
    let activeStatusLabel: String
    let isFocused: Bool
    var dimUnfocusedTitle: Bool = false
    var compactForQuickPanel: Bool = false
    let action: () -> Void

    var body: some View {
        let title = compactForQuickPanel
            ? candidate.inPlayerQuickRowTitle
            : candidate.quickRowTitle(roomName: roomName, isRecommended: isRecommended)
        let subtitle: String = {
            if compactForQuickPanel {
                return candidate.inPlayerQuickRowSubtitle(
                    isRecommended: isRecommended,
                    activeLabel: isSelected ? activeStatusLabel : nil
                )
            }
            let baseSubtitle = candidate.quickRowMetadata(activeLabel: isSelected ? activeStatusLabel : nil)
            return (candidate.isNorwegian == true) ? "Norsk · \(baseSubtitle)" : baseSubtitle
        }()

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
