import Foundation
import Observation
import SwiftUI

public struct SourcePickerContext: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let itemId: String
    public let title: String
    public let seriesTitle: String?
    public let season: Int?
    public let episode: Int?
    public let startPositionSeconds: Double?
    public let existingPrepareToken: String?
    public let backdropUrl: String?
    public let logoUrl: String?

    public init(
        itemId: String,
        title: String,
        seriesTitle: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        startPositionSeconds: Double? = nil,
        existingPrepareToken: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil
    ) {
        self.id = "\(itemId)#\(UUID().uuidString)"
        self.itemId = itemId
        self.title = title
        self.seriesTitle = seriesTitle
        let parsed = EpisodeTitleFormatter.resolveSeasonAndEpisode(
            itemId: itemId,
            season: season,
            episode: episode
        )
        self.season = parsed.season
        self.episode = parsed.episode
        self.startPositionSeconds = startPositionSeconds
        self.existingPrepareToken = existingPrepareToken
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
    }

    public var apiTitle: String {
        EpisodeTitleFormatter.apiEpisodeTitle(
            rawTitle: title,
            seriesTitle: seriesTitle,
            itemId: itemId,
            season: season,
            episode: episode
        )
    }

    public var displaySubject: String {
        EpisodeTitleFormatter.sourcePickerSubject(
            title: title,
            seriesTitle: seriesTitle,
            itemId: itemId,
            season: season,
            episode: episode
        )
    }
}

internal enum SourcePickerTokenPolicy {
    nonisolated static let adoptInflightDefaultSentinel = "__luna_adopt_default_inflight__"

    nonisolated static func effectiveExistingPrepareToken(
        rawExistingToken: String?,
        existingTokenFailed: Bool
    ) -> String? {
        guard !existingTokenFailed,
              let existing = rawExistingToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !existing.isEmpty else {
            return nil
        }
        return existing
    }
}

internal protocol SourcePickerSessionClient: Sendable {
    func preparePlayback(
        itemId: String,
        title: String,
        seriesTitle: String?,
        startPositionSeconds: Double?,
        prepareToken: String?
    ) async throws -> TvPrepareResponse
    func cancelInflightPlayback(
        sessionId: String?,
        resolveId: String?,
        itemId: String?,
        prepareToken: String?
    ) async throws
    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse
    func fetchItemCandidates(
        itemId: String,
        title: String,
        seriesTitle: String?
    ) async throws -> TvAlternativesResponse
    func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool?
    ) async throws -> TvHeartbeatResponse
}

extension SourcePickerSessionClient {
    func fetchItemCandidates(
        itemId: String,
        title: String,
        seriesTitle: String?
    ) async throws -> TvAlternativesResponse {
        throw LunaCoreError.serverMessage(404, "unsupported")
    }
}

extension LunaCoreClient: SourcePickerSessionClient {}

@MainActor
@Observable
internal final class SourcePickerViewModel {
    private(set) var candidates: [TvCandidateInfo] = []
    private(set) var activeCandidateId: String?
    @ObservationIgnored private(set) var resolvedPrepareToken: String?
    @ObservationIgnored private(set) var existingTokenFailed: Bool = false
    @ObservationIgnored private(set) var createdOrphanSessionId: String?
    @ObservationIgnored private(set) var createdPreparedSession: TvPlaybackSession?
    @ObservationIgnored private(set) var inflightPrepareToken: String?
    @ObservationIgnored private(set) var loadedViaFastItemCandidates: Bool = false
    @ObservationIgnored private(set) var didSelectCandidate: Bool = false
    private(set) var isLoading: Bool = true
    private(set) var errorMessage: String?
    @ObservationIgnored private(set) var isDismissed: Bool = false

    func handleAppear() {
        isDismissed = false
    }

    func loadCandidates(
        context: SourcePickerContext,
        client: (any SourcePickerSessionClient)?,
        onUnauthorized: () -> Void
    ) async {
        guard !Task.isCancelled, !isDismissed else { return }
        if !didSelectCandidate {
            stopOrphanSessionIfNeeded(context: context, client: client)
        }
        guard let client else {
            isLoading = false
            errorMessage = "Mangler tilkobling til LunaCore."
            return
        }
        isLoading = true
        errorMessage = nil

        var usedExistingToken = false
        loadedViaFastItemCandidates = false
        do {
            let sessionToken: String
            if let existing = SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: context.existingPrepareToken,
                existingTokenFailed: existingTokenFailed
            ) {
                sessionToken = existing
                resolvedPrepareToken = existing
                createdPreparedSession = nil
                usedExistingToken = true
            } else {
                do {
                    let fastAlt = try await client.fetchItemCandidates(
                        itemId: context.itemId,
                        title: context.apiTitle,
                        seriesTitle: context.seriesTitle
                    )
                    if Task.isCancelled || isDismissed { return }
                    let nonEmptySid = fastAlt.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
                    resolvedPrepareToken = nonEmptySid.isEmpty ? nil : nonEmptySid
                    createdOrphanSessionId = nil
                    createdPreparedSession = nil
                    loadedViaFastItemCandidates = true
                    candidates = fastAlt.alternatives
                    activeCandidateId = fastAlt.activeCandidateId
                        ?? fastAlt.alternatives.first(where: { $0.isActive == true })?.candidateId
                    isLoading = false
                    return
                } catch let LunaCoreError.serverMessage(status, _) where status == 404 || status == 405 {
                    // Fallback to full prepare + alternatives on older servers without /playback/candidates
                }

                let reqToken = UUID().uuidString
                inflightPrepareToken = reqToken
                defer {
                    if inflightPrepareToken == reqToken {
                        inflightPrepareToken = nil
                    }
                }
                let prep = try await client.preparePlayback(
                    itemId: context.itemId,
                    title: context.apiTitle,
                    seriesTitle: context.seriesTitle,
                    startPositionSeconds: context.startPositionSeconds,
                    prepareToken: reqToken
                )
                if Task.isCancelled || isDismissed {
                    if let orphanSid = prep.playbackSession?.sessionId {
                        Self.stopSessionDetached(sessionId: orphanSid, client: client)
                    }
                    return
                }
                guard let tok = prep.prepareToken, !tok.isEmpty else {
                    if let orphanSid = prep.playbackSession?.sessionId {
                        Self.stopSessionDetached(sessionId: orphanSid, client: client)
                    }
                    candidates = []
                    isLoading = false
                    return
                }
                sessionToken = tok
                resolvedPrepareToken = tok
                createdOrphanSessionId = prep.playbackSession?.sessionId
                createdPreparedSession = prep.playbackSession
            }

            if Task.isCancelled || isDismissed {
                if !didSelectCandidate {
                    stopOrphanSessionIfNeeded(context: context, client: client)
                }
                return
            }

            let alt = try await client.fetchAlternatives(sessionId: sessionToken)
            if Task.isCancelled || isDismissed {
                if !didSelectCandidate {
                    stopOrphanSessionIfNeeded(context: context, client: client)
                }
                return
            }
            candidates = alt.alternatives
            activeCandidateId = alt.activeCandidateId
                ?? alt.alternatives.first(where: { $0.isActive == true })?.candidateId
        } catch is CancellationError {
            if !didSelectCandidate {
                stopOrphanSessionIfNeeded(context: context, client: client)
            }
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            if !didSelectCandidate {
                stopOrphanSessionIfNeeded(context: context, client: client)
            }
            return
        } catch LunaCoreError.unauthorized {
            if !didSelectCandidate {
                stopOrphanSessionIfNeeded(context: context, client: client)
            }
            if !Task.isCancelled && !isDismissed {
                onUnauthorized()
            }
        } catch {
            if !didSelectCandidate {
                stopOrphanSessionIfNeeded(context: context, client: client)
            }
            if Task.isCancelled || isDismissed {
                return
            }
            if usedExistingToken {
                existingTokenFailed = true
                resolvedPrepareToken = nil
            }
            errorMessage = LunaCopy.friendlyErrorMessage(error)
        }
        isLoading = false
    }

    func selectCandidate(
        _ candidate: TvCandidateInfo,
        isCurrent: Bool,
        context: SourcePickerContext,
        client: (any SourcePickerSessionClient)?,
        onSelectCandidate: (TvCandidateInfo, String?, TvPlaybackSession?) -> Void
    ) {
        didSelectCandidate = true
        if isCurrent, let tok = resolvedPrepareToken, !tok.isEmpty {
            let handedOverSession = createdPreparedSession
            createdOrphanSessionId = nil
            createdPreparedSession = nil
            onSelectCandidate(candidate, tok, handedOverSession)
        } else if isCurrent, loadedViaFastItemCandidates {
            onSelectCandidate(candidate, SourcePickerTokenPolicy.adoptInflightDefaultSentinel, nil)
        } else {
            stopOrphanSessionIfNeeded(context: context, client: client)
            onSelectCandidate(candidate, nil, nil)
        }
    }

    func handleDisappear(
        context: SourcePickerContext,
        client: (any SourcePickerSessionClient)?
    ) {
        isDismissed = true
        if !didSelectCandidate {
            stopOrphanSessionIfNeeded(context: context, client: client)
        }
    }

    func stopOrphanSessionIfNeeded(
        context: SourcePickerContext,
        client: (any SourcePickerSessionClient)?
    ) {
        let activeExistingToken = SourcePickerTokenPolicy.effectiveExistingPrepareToken(
            rawExistingToken: context.existingPrepareToken,
            existingTokenFailed: existingTokenFailed
        )
        guard activeExistingToken == nil, let client else {
            return
        }
        if let pendingToken = inflightPrepareToken {
            inflightPrepareToken = nil
            let targetItemId = context.itemId
            Task.detached(priority: .utility) {
                try? await client.cancelInflightPlayback(
                    sessionId: nil,
                    resolveId: nil,
                    itemId: targetItemId,
                    prepareToken: pendingToken
                )
            }
        }
        guard let sid = createdOrphanSessionId else {
            createdPreparedSession = nil
            return
        }
        createdOrphanSessionId = nil
        createdPreparedSession = nil
        Self.stopSessionDetached(sessionId: sid, client: client)
    }

    private static func stopSessionDetached(
        sessionId: String,
        client: any SourcePickerSessionClient
    ) {
        Task.detached(priority: .utility) {
            _ = try? await client.sendHeartbeat(
                sessionId: sessionId,
                state: "stopped",
                positionSeconds: 0,
                durationSeconds: 0,
                completed: nil
            )
        }
    }
}

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
                                roomName: sessionStore.roomName,
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
