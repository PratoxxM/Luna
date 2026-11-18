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
            errorMessage = error.localizedDescription
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
        guard (context.existingPrepareToken == nil || existingTokenFailed),
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

    var body: some View {
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Velg avspillingskilde")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(LunaTheme.linen)

                        Text("\(context.displaySubject) · Rangert for \(sessionStore.roomName) (\(sessionStore.activePreset.shortBadgeLabel))")
                            .font(.callout)
                            .foregroundStyle(LunaTheme.muted)
                    }

                    Spacer()

                    LunaPillButton("Lukk", systemImage: "xmark", prominence: .subtleChip) {
                        onCancel()
                    }
                }

                if viewModel.isLoading {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Søker etter beste lokale og Usenet-kilder…")
                            .font(.headline)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    Spacer()
                    VStack(spacing: 18) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(LunaTheme.amber)
                        Text(errorMessage)
                            .font(.callout)
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
                        .font(.headline)
                        .foregroundStyle(LunaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                                let isCurrent = viewModel.activeCandidateId != nil
                                    ? (candidate.candidateId == viewModel.activeCandidateId)
                                    : (candidate.isActive == true)
                                CandidateRowButton(
                                    candidate: candidate,
                                    isRecommended: index == 0,
                                    isCurrentWinner: isCurrent
                                ) {
                                    viewModel.selectCandidate(
                                        candidate,
                                        isCurrent: isCurrent,
                                        context: context,
                                        client: sessionStore.makeClient(),
                                        onSelectCandidate: onSelectCandidate
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(56)
        }
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            viewModel.handleAppear()
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

private struct CandidateRowButton: View {
    let candidate: TvCandidateInfo
    let isRecommended: Bool
    let isCurrentWinner: Bool
    let onPick: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 20) {
                Image(systemName: isCurrentWinner ? "checkmark.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isFocused || isCurrentWinner ? LunaTheme.amber : LunaTheme.moonlight)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(candidate.displayHeadline)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(LunaTheme.linen)
                            .lineLimit(1)

                        if isRecommended {
                            Text("Anbefalt")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(LunaTheme.canvas)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(LunaTheme.amber, in: Capsule())
                        }
                    }

                    Text(candidate.releaseTitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(isFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 12) {
                    if let size = candidate.formattedSize {
                        Text(size)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(LunaTheme.moonlight)
                    }

                    Text(candidate.sourceBadgeLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            isFocused ? LunaTheme.amber.opacity(0.22) : LunaTheme.warmBorderBase.opacity(0.09),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isFocused ? LunaTheme.amber.opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                        )
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .fill(
                        isFocused
                            ? LunaTheme.surfaceElevated
                            : (isCurrentWinner ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? LunaTheme.focusGoldBorder
                            : (isCurrentWinner ? LunaTheme.warmBorderStrong : LunaTheme.warmBorder),
                        lineWidth: isFocused ? 2.2 : 1.0
                    )
            )
            .shadow(
                color: isFocused ? Color.black.opacity(0.36) : .clear,
                radius: isFocused ? 12 : 0,
                x: 0,
                y: isFocused ? 5 : 0
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
