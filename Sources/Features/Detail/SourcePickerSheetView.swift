import Foundation
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
        startPositionSeconds: Double?
    ) async throws -> TvPrepareResponse
    func fetchAlternatives(sessionId: String) async throws -> TvAlternativesResponse
    func sendHeartbeat(
        sessionId: String,
        state: String,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool?
    ) async throws -> TvHeartbeatResponse
}

extension LunaCoreClient: SourcePickerSessionClient {}

@MainActor
internal final class SourcePickerViewModel: ObservableObject {
    @Published private(set) var candidates: [TvCandidateInfo] = []
    @Published private(set) var activeCandidateId: String?
    @Published private(set) var resolvedPrepareToken: String?
    @Published private(set) var existingTokenFailed: Bool = false
    @Published private(set) var createdOrphanSessionId: String?
    @Published private(set) var didSelectCandidate: Bool = false
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String?
    private(set) var isDismissed: Bool = false

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
        do {
            let sessionToken: String
            if let existing = SourcePickerTokenPolicy.effectiveExistingPrepareToken(
                rawExistingToken: context.existingPrepareToken,
                existingTokenFailed: existingTokenFailed
            ) {
                sessionToken = existing
                resolvedPrepareToken = existing
                usedExistingToken = true
            } else {
                let prep = try await client.preparePlayback(
                    itemId: context.itemId,
                    title: context.apiTitle,
                    seriesTitle: context.seriesTitle,
                    startPositionSeconds: context.startPositionSeconds
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
        onSelectCandidate: (TvCandidateInfo, String?) -> Void
    ) {
        didSelectCandidate = true
        if isCurrent, let tok = resolvedPrepareToken {
            createdOrphanSessionId = nil
            onSelectCandidate(candidate, tok)
        } else {
            stopOrphanSessionIfNeeded(context: context, client: client)
            onSelectCandidate(candidate, nil)
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
        guard activeExistingToken == nil,
              let sid = createdOrphanSessionId,
              let client else {
            return
        }
        createdOrphanSessionId = nil
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
    @EnvironmentObject private var sessionStore: AppSessionStore

    let context: SourcePickerContext
    let onSelectCandidate: (TvCandidateInfo, String?) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = SourcePickerViewModel()
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

        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Velg kilde")
                        .font(LunaTheme.Font.pageTitle)
                        .foregroundStyle(LunaTheme.linen)

                    Text("\(context.displaySubject) · Tilpasset \(sessionStore.roomName)")
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(LunaTheme.muted)
                }

                if viewModel.isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Søker etter tilgjengelige kilder…")
                            .font(LunaTheme.Font.cardTitle)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    Spacer()
                    VStack(spacing: 18) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(LunaTheme.Font.largeStatusIcon)
                            .foregroundStyle(LunaTheme.danger)
                        Text(errorMessage)
                            .font(LunaTheme.Font.body)
                            .foregroundStyle(LunaTheme.moonlight)
                            .multilineTextAlignment(.center)
                        LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                            reloadAttempt &+= 1
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else if viewModel.candidates.isEmpty {
                    Spacer()
                    Text("Fant ingen tilgjengelige kilder for denne tittelen.")
                        .font(LunaTheme.Font.cardTitle)
                        .foregroundStyle(LunaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 14) {
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
                            }
                        }
                        .frame(maxWidth: 1020)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                    .scrollClipDisabled()
                    .defaultFocus($focusedCandidateID, defaultID, priority: .userInitiated)
                    .focusScope(sourcePickerFocusNamespace)
                }
            }
            .padding(56)
        }
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            viewModel.handleAppear()
            if let defaultID {
                focusedCandidateID = defaultID
            }
        }
        .onChange(of: viewModel.candidates.map(\.id)) { _, _ in
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
