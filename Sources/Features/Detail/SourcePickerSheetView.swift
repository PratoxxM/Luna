import SwiftUI

struct SourcePickerSheetView: View {
    @Environment(AppSessionStore.self) private var sessionStore

    let context: SourcePickerContext
    let onSelectCandidate: (TvCandidateInfo, String?, TvPlaybackSession?) -> Void
    let onCancel: () -> Void

    @State private var viewModel = SourcePickerViewModel()
    @State private var reloadAttempt: Int = 0
    @FocusState private var focusedCandidateID: String?
    @Namespace private var sourcePickerFocusNamespace

    private var preferredDefaultCandidateID: String? {
        if let active = viewModel.activeCandidateId,
           viewModel.candidates.contains(where: { $0.candidateId == active }) {
            return active
        }
        if let marked = viewModel.candidates.first(where: { $0.isActive == true }) {
            return marked.id
        }
        return viewModel.candidates.first?.id
    }

    var body: some View {
        let defaultID = preferredDefaultCandidateID

        LunaSheetContainer(
            title: "Velg utgave",
            subtitle: context.displaySubject,
            width: .wide,
            maxHeight: 860,
            onClose: onCancel
        ) {
            if viewModel.isLoading {
                LunaLoadingRow(message: "Henter tilgjengelige utgaver…")
            } else if let errorMessage = viewModel.errorMessage {
                LunaInlineError(message: errorMessage) {
                    reloadAttempt &+= 1
                }
            } else if viewModel.candidates.isEmpty {
                LunaEmptyState(headline: "Fant ingen tilgjengelige utgaver for denne tittelen.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LunaListGroup(showsSurface: false) {
                        ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                            let isCurrent = viewModel.activeCandidateId != nil
                                ? (candidate.candidateId == viewModel.activeCandidateId)
                                : (candidate.isActive == true)
                            SourceCandidateRowView(
                                candidate: candidate,
                                isRecommended: index == 0,
                                isSelected: isCurrent,
                                activeStatusLabel: "Forhåndsvalgt",
                                isFocused: focusedCandidateID == candidate.id
                            ) {
                                viewModel.selectCandidate(
                                    candidate,
                                    isCurrent: isCurrent,
                                    context: context,
                                    client: sessionStore.makeClient(),
                                    onSelectCandidate: onSelectCandidate
                                )
                            }
                            .focused($focusedCandidateID, equals: candidate.id)
                            .prefersDefaultFocus(candidate.id == defaultID, in: sourcePickerFocusNamespace)

                            if index < viewModel.candidates.count - 1 {
                                LunaListDivider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
                .defaultFocus($focusedCandidateID, defaultID, priority: .userInitiated)
                .focusScope(sourcePickerFocusNamespace)
            }
        }
        .onAppear {
            viewModel.handleAppear()
            if let defaultID {
                focusedCandidateID = defaultID
            }
        }
        .onChange(of: viewModel.candidates) { _, _ in
            if let defaultID {
                focusedCandidateID = defaultID
            }
        }
        .task(id: reloadAttempt) {
            await loadCandidates()
        }
        .onDisappear {
            viewModel.handleDisappear(
                context: context,
                client: sessionStore.makeClient()
            )
        }
    }

    private func loadCandidates() async {
        await viewModel.loadCandidates(
            context: context,
            client: sessionStore.makeClient(),
            onUnauthorized: {
                sessionStore.unpairDevice()
                onCancel()
            }
        )
    }
}
