import SwiftUI

struct SourcePickerSheetView: View {
    @Environment(AppSessionStore.self) private var sessionStore

    let context: SourcePickerContext
    let onSelectCandidate: (TvCandidateInfo, String?, TvPlaybackSession?) -> Void
    let onCancel: () -> Void

    @State private var viewModel = SourcePickerViewModel()
    @State private var reloadAttempt: Int = 0
    @State private var focusNonce: Int = 0
    @FocusState private var focusedCandidateID: String?
    @Namespace private var sourcePickerFocusNamespace

    nonisolated static func preferredDefaultCandidateID(
        candidates: [TvCandidateInfo],
        activeCandidateId: String?
    ) -> String? {
        if let active = activeCandidateId,
           candidates.contains(where: { $0.candidateId == active }) {
            return active
        }
        if let marked = candidates.first(where: { $0.isActive == true }) {
            return marked.id
        }
        return candidates.first?.id
    }

    nonisolated static func shouldTriggerDefaultFocus(
        wasLoading: Bool,
        isLoading: Bool,
        errorMessage: String?,
        candidates: [TvCandidateInfo]
    ) -> Bool {
        wasLoading && !isLoading && errorMessage == nil && !candidates.isEmpty
    }

    private var preferredDefaultCandidateID: String? {
        Self.preferredDefaultCandidateID(
            candidates: viewModel.candidates,
            activeCandidateId: viewModel.activeCandidateId
        )
    }

    var body: some View {
        let defaultID = preferredDefaultCandidateID
        let hasInteractiveCandidates = !viewModel.isLoading && viewModel.errorMessage == nil && !viewModel.candidates.isEmpty

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
                .defaultFocus($focusedCandidateID, defaultID, priority: .userInitiated)
                .focusScope(sourcePickerFocusNamespace)
                .lunaEntryFocusTarget(
                    nonce: focusNonce,
                    isActive: hasInteractiveCandidates,
                    focus: $focusedCandidateID,
                    target: { preferredDefaultCandidateID }
                )
            }
        }
        .onAppear {
            viewModel.handleAppear()
            if hasInteractiveCandidates {
                focusNonce &+= 1
            }
        }
        .onChange(of: viewModel.isLoading) { wasLoading, isLoading in
            if isLoading {
                focusedCandidateID = nil
            } else if Self.shouldTriggerDefaultFocus(
                wasLoading: wasLoading,
                isLoading: isLoading,
                errorMessage: viewModel.errorMessage,
                candidates: viewModel.candidates
            ) {
                focusNonce &+= 1
            }
        }
        .onChange(of: defaultID) { _, newDefaultID in
            if hasInteractiveCandidates, focusedCandidateID == nil, newDefaultID != nil {
                focusNonce &+= 1
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
