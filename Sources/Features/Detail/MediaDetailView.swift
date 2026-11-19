import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var sessionStore: AppSessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.dismiss) private var dismiss

    let mediaType: String
    let itemId: String
    let initialTitle: String

    @StateObject private var viewModel: MediaDetailViewModel
    @State private var subpageToken = UUID()
    @State private var modalToken = UUID()

    @Namespace private var detailFocusNamespace

    private let detailGutter: CGFloat = 90

    init(mediaType: String, itemId: String, initialTitle: String) {
        self.mediaType = mediaType
        self.itemId = itemId
        self.initialTitle = initialTitle
        _viewModel = StateObject(
            wrappedValue: MediaDetailViewModel(
                mediaType: mediaType,
                itemId: itemId,
                initialTitle: initialTitle
            )
        )
    }

    private var scopeKey: String {
        "\(mediaType)#\(itemId)#\(sessionStore.roomName)#\(sessionStore.effectiveHardwareProfile)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LunaTheme.canvas.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    if let detail = viewModel.detail {
                        DetailHeroHeaderView(
                            item: detail,
                            client: viewModel.client,
                            primaryPlayTitle: viewModel.primaryPlayLabel(detail),
                            watchedButtonTitle: viewModel.watchedButtonTitle(detail),
                            isPreResolvedReady: viewModel.isPreResolvedReady,
                            horizontalGutter: detailGutter,
                            focusNamespace: detailFocusNamespace,
                            hasLocalEpisodes: viewModel.hasLocalEpisodes,
                            onPlay: {
                                viewModel.launchPrimaryPlayback()
                            },
                            onToggleWatchlist: {
                                Task { await viewModel.toggleWatchlist() }
                            },
                            onToggleWatched: {
                                Task { await viewModel.handleHeroWatchedTap() }
                            },
                            onToggleMonitor: {
                                Task { await viewModel.toggleMonitor() }
                            },
                            onPickSource: {
                                viewModel.openPrimarySourcePicker()
                            },
                            onDeleteTitle: {
                                viewModel.requestDeleteTitle()
                            }
                        )

                        if detail.mediaType == "series", let seasons = detail.seasons, !seasons.isEmpty {
                            DetailSeasonsSectionView(
                                detail: detail,
                                seasons: seasons,
                                selectedSeasonNumber: $viewModel.selectedSeasonNumber,
                                episodes: viewModel.episodes,
                                isLoadingEpisodes: viewModel.isLoadingEpisodes,
                                client: viewModel.client,
                                detailGutter: detailGutter,
                                onSelectSeason: { seasonNumber in
                                    Task { await viewModel.selectSeason(seasonNumber) }
                                },
                                onPlayEpisode: { ep in
                                    viewModel.playEpisode(ep)
                                },
                                onPickEpisodeSource: { ep in
                                    viewModel.openEpisodeSourcePicker(ep)
                                },
                                onToggleEpisodeWatched: { ep in
                                    Task { await viewModel.toggleEpisodeWatched(ep) }
                                },
                                onDeleteSeason: { seasonNum in
                                    viewModel.requestDeleteSeason(seasonNum)
                                },
                                onDeleteEpisode: { ep in
                                    viewModel.requestDeleteEpisode(ep)
                                }
                            )
                        }
                    } else if viewModel.isLoading {
                        HStack(spacing: 16) {
                            ProgressView()
                            Text("Henter detaljer for \(initialTitle)…")
                                .font(.title3)
                                .foregroundStyle(LunaTheme.moonlight)
                        }
                        .padding(.horizontal, detailGutter)
                        .padding(.top, 180)
                    } else if let errorMessage = viewModel.errorMessage {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(errorMessage)
                                .foregroundStyle(LunaTheme.danger)
                            LunaPillButton("Prøv igjen", systemImage: "arrow.clockwise") {
                                Task { await viewModel.reloadFromError() }
                            }
                        }
                        .padding(.horizontal, detailGutter)
                        .padding(.top, 180)
                    }
                }
                .padding(.bottom, viewModel.detail?.mediaType == "series" ? 84 : 0)
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.zero, for: .scrollContent)
            .ignoresSafeArea(edges: [.top, .horizontal])

            if let mutationErrorBanner = viewModel.mutationErrorBanner {
                TransientErrorBanner(message: mutationErrorBanner)
                    .padding(.horizontal, detailGutter)
                    .padding(.top, 72)
            }
        }
        .lunaNavigationContainerBackdrop(mode: .probeOnly)
        .focusScope(detailFocusNamespace)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $viewModel.pendingDeleteTarget) { target in
            DetailDeleteSheetView(
                target: target,
                onPrepareBeforePreflight: {
                    viewModel.prepareForDeletePreflight()
                },
                onDeleted: { _ in
                    Task {
                        if await viewModel.handleDeleted(target: target) {
                            dismiss()
                        }
                    }
                },
                onCancel: {
                    viewModel.pendingDeleteTarget = nil
                }
            )
            .environmentObject(sessionStore)
            .preferredColorScheme(.dark)
        }
        .sheet(item: $viewModel.sourcePickerContext) { ctx in
            SourcePickerSheetView(
                context: ctx,
                onSelectCandidate: { picked, reusedToken in
                    viewModel.launchSelectedSource(picked, reusedToken: reusedToken, context: ctx)
                },
                onCancel: {
                    viewModel.sourcePickerContext = nil
                }
            )
            .environmentObject(sessionStore)
            .environmentObject(sessionStore.comfort)
            .preferredColorScheme(.dark)
        }
        .confirmationDialog(
            viewModel.pendingSeriesWatchedItem?.watched == true
                ? "Marker hele serien som usett?"
                : "Marker hele serien som sett?",
            isPresented: Binding(
                get: { viewModel.pendingSeriesWatchedItem != nil },
                set: { if !$0 { viewModel.pendingSeriesWatchedItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = viewModel.pendingSeriesWatchedItem {
                Button(item.watched ? "Marker hele serien som usett" : "Marker hele serien som sett") {
                    Task { await viewModel.confirmSeriesWatched(item) }
                }
                Button("Avbryt", role: .cancel) {
                    viewModel.pendingSeriesWatchedItem = nil
                }
            }
        }
        .onAppear {
            viewModel.bind(sessionContext: sessionStore)
            subpageVisibility.enterSubpage(subpageToken)
        }
        .onChange(of: viewModel.isShowingModal) { _, isShowingModal in
            if isShowingModal {
                subpageVisibility.enterModal(modalToken)
            } else {
                subpageVisibility.leaveModal(modalToken)
                subpageVisibility.enterSubpage(subpageToken)
            }
        }
        .task(id: scopeKey) {
            await viewModel.handleTaskAppearance(scopeKey: scopeKey, sessionContext: sessionStore)
        }
        .onChange(of: sessionStore.homeRefreshNonce) { _, newNonce in
            viewModel.handleHomeRefreshNonceChange(newNonce)
        }
        .onChange(of: sessionStore.activePlaybackTarget) { oldTarget, newTarget in
            viewModel.handlePlaybackTargetChange(oldTarget: oldTarget, newTarget: newTarget)
        }
        .onDisappear {
            viewModel.handleDisappear(sessionContext: sessionStore)
            let isLaunchingPlayback = sessionStore.activePlaybackTarget != nil
            let isShowingModal = viewModel.isShowingModal
            if !isShowingModal {
                subpageVisibility.leaveModal(modalToken)
            }
            if SubpageVisibilityPolicy.shouldLeaveSubpageOnDisappear(
                hasPushedChildDestination: false,
                hasActivePlayback: isLaunchingPlayback,
                isShowingModalSheet: isShowingModal
            ) {
                subpageVisibility.leaveSubpage(subpageToken)
            }
        }
    }
}
