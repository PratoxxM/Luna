import SwiftUI

public struct SourcePickerContext: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let itemId: String
    public let title: String
    public let seriesTitle: String?
    public let startPositionSeconds: Double?
    public let existingPrepareToken: String?
    public let backdropUrl: String?
    public let logoUrl: String?

    public init(
        itemId: String,
        title: String,
        seriesTitle: String? = nil,
        startPositionSeconds: Double? = nil,
        existingPrepareToken: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil
    ) {
        self.id = "\(itemId)#\(UUID().uuidString)"
        self.itemId = itemId
        self.title = title
        self.seriesTitle = seriesTitle
        self.startPositionSeconds = startPositionSeconds
        self.existingPrepareToken = existingPrepareToken
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
    }
}

struct SourcePickerSheetView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore

    let context: SourcePickerContext
    let onSelectCandidate: (TvCandidateInfo, String?) -> Void
    let onCancel: () -> Void

    @State private var candidates: [TvCandidateInfo] = []
    @State private var activeCandidateId: String?
    @State private var resolvedPrepareToken: String?
    @State private var createdOrphanSessionId: String?
    @State private var didSelectCandidate: Bool = false
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LunaTheme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Velg avspillingskilde")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        Text("\(context.seriesTitle ?? context.title) · Rangert for \(sessionStore.roomName) (\(sessionStore.activePreset.shortBadgeLabel))")
                            .font(.callout)
                            .foregroundStyle(LunaTheme.muted)
                    }

                    Spacer()

                    LunaPillButton("Lukk", systemImage: "xmark", prominence: .subtleChip) {
                        onCancel()
                    }
                }

                if isLoading {
                    Spacer()
                    HStack(spacing: 16) {
                        ProgressView()
                        Text("Søker etter beste lokale og Usenet-kilder…")
                            .font(.headline)
                            .foregroundStyle(LunaTheme.moonlight)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else if let errorMessage {
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
                            Task { await loadCandidates() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else if candidates.isEmpty {
                    Spacer()
                    Text("Fant ingen tilgjengelige kilder for denne tittelen.")
                        .font(.headline)
                        .foregroundStyle(LunaTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                                let isCurrent = activeCandidateId != nil
                                    ? (candidate.candidateId == activeCandidateId)
                                    : (candidate.isActive == true)
                                CandidateRowButton(
                                    candidate: candidate,
                                    isRecommended: index == 0,
                                    isCurrentWinner: isCurrent
                                ) {
                                    didSelectCandidate = true
                                    if isCurrent, let tok = resolvedPrepareToken {
                                        createdOrphanSessionId = nil
                                        onSelectCandidate(candidate, tok)
                                    } else {
                                        stopOrphanSessionIfNeeded()
                                        onSelectCandidate(candidate, nil)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(56)
        }
        .task {
            await loadCandidates()
        }
        .onDisappear {
            if !didSelectCandidate {
                stopOrphanSessionIfNeeded()
            }
        }
    }

    private func stopOrphanSessionIfNeeded() {
        guard context.existingPrepareToken == nil,
              let sid = createdOrphanSessionId,
              let client = sessionStore.makeClient() else {
            return
        }
        createdOrphanSessionId = nil
        Task.detached(priority: .utility) {
            _ = try? await client.sendHeartbeat(
                sessionId: sid,
                state: "stopped",
                positionSeconds: 0,
                durationSeconds: 0
            )
        }
    }

    private func loadCandidates() async {
        guard let client = sessionStore.makeClient() else {
            isLoading = false
            errorMessage = "Mangler tilkobling til MediaOS."
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            let sessionToken: String
            if let existing = context.existingPrepareToken, !existing.isEmpty {
                sessionToken = existing
                resolvedPrepareToken = existing
            } else {
                let prep = try await client.preparePlayback(
                    itemId: context.itemId,
                    title: context.title,
                    seriesTitle: context.seriesTitle,
                    startPositionSeconds: context.startPositionSeconds
                )
                guard let tok = prep.prepareToken, !tok.isEmpty else {
                    candidates = []
                    isLoading = false
                    return
                }
                sessionToken = tok
                resolvedPrepareToken = tok
                createdOrphanSessionId = prep.playbackSession?.sessionId
            }

            let alt = try await client.fetchAlternatives(sessionId: sessionToken)
            candidates = alt.alternatives
            activeCandidateId = alt.activeCandidateId
                ?? alt.alternatives.first(where: { $0.isActive == true })?.candidateId
        } catch MediaOSError.unauthorized {
            sessionStore.unpairDevice()
            onCancel()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
                    .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.amber)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(candidate.displayHeadline)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(isFocused ? LunaTheme.canvas : .white)
                            .lineLimit(1)

                        if isRecommended {
                            Text("Anbefalt")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.canvas)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(
                                    isFocused ? LunaTheme.canvas : LunaTheme.amber,
                                    in: Capsule()
                                )
                        }
                    }

                    Text(candidate.releaseTitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(isFocused ? LunaTheme.canvas.opacity(0.78) : LunaTheme.muted)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 12) {
                    if let size = candidate.formattedSize {
                        Text(size)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isFocused ? LunaTheme.canvas : LunaTheme.moonlight)
                    }

                    Text(candidate.sourceBadgeLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.moonlight)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            isFocused ? LunaTheme.canvas.opacity(0.85) : Color.white.opacity(0.10),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFocused ? LunaTheme.amber : LunaTheme.surfaceRaised.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.white.opacity(0.9) : LunaTheme.moonlight.opacity(0.12),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
