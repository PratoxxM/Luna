import SwiftUI

struct MediaDetailView: View {
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(\.lunaSubpageVisibility) private var subpageVisibility
    @Environment(\.dismiss) private var dismiss

    let mediaType: String
    let itemId: String
    let initialTitle: String

    @State private var viewModel: MediaDetailViewModel
    @State private var subpageToken = UUID()
    @State private var modalToken = UUID()
    @State private var pendingMoreAction: PendingMoreSheetAction?

    private enum PendingMoreSheetAction {
        case readOverview
        case toggleWatched
        case deleteSeason(Int)
        case deleteTitle
    }

    @Namespace private var detailFocusNamespace

    private let detailGutter: CGFloat = LunaTheme.horizontalGutter

    init(mediaType: String, itemId: String, initialTitle: String) {
        self.mediaType = mediaType
        self.itemId = itemId
        self.initialTitle = initialTitle
        _viewModel = State(
            initialValue: MediaDetailViewModel(
                mediaType: mediaType,
                itemId: itemId,
                initialTitle: initialTitle
            )
        )
    }

    private var scopeKey: String {
        "\(mediaType)#\(itemId)#\(sessionStore.roomName)#\(sessionStore.hardwareProfile)"
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .topLeading) {
            LunaTheme.canvas.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LunaTokens.Layout.blockGap) {
                    if let detail = viewModel.detail {
                        DetailHeroHeaderView(
                            item: detail,
                            client: viewModel.client,
                            primaryPlayTitle: viewModel.heroPrimaryPlayTitle(detail),
                            horizontalGutter: detailGutter,
                            focusNamespace: detailFocusNamespace,
                            onPlay: {
                                viewModel.launchPrimaryPlayback()
                            },
                            onToggleWatchlist: {
                                Task { await viewModel.toggleWatchlist() }
                            },
                            onPickSource: {
                                viewModel.openPrimarySourcePicker()
                            },
                            onOpenMore: {
                                viewModel.showMoreSheet = true
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
                                onDeleteEpisode: { ep in
                                    viewModel.requestDeleteEpisode(ep)
                                }
                            )
                        }
                    } else if viewModel.isLoading {
                        LunaLoadingRow(message: "Henter detaljer for \(initialTitle)…")
                            .padding(.horizontal, detailGutter)
                            .padding(.top, 140)
                    } else if let errorMessage = viewModel.errorMessage {
                        LunaInlineError(message: errorMessage) {
                            Task { await viewModel.reloadFromError() }
                        }
                        .padding(.horizontal, detailGutter)
                        .padding(.top, 140)
                    }
                }
                .padding(.bottom, viewModel.detail?.mediaType == "series" ? 84 : 0)
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.zero, for: .scrollContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
        }
        .lunaBottomToast(message: $viewModel.mutationErrorBanner, tone: .danger)
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
            .environment(sessionStore)
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
            .environment(sessionStore)
            .environment(sessionStore.comfort)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $viewModel.showMoreSheet, onDismiss: {
            let action = pendingMoreAction
            pendingMoreAction = nil
            switch action {
            case .readOverview:
                viewModel.showFullOverviewSheet = true
            case .toggleWatched:
                Task { await viewModel.handleHeroWatchedTap() }
            case .deleteSeason(let seasonNumber):
                viewModel.requestDeleteSeason(seasonNumber)
            case .deleteTitle:
                viewModel.requestDeleteTitle()
            case nil:
                break
            }
        }) {
            if let detail = viewModel.detail {
                let hasLocalEpisodes = viewModel.hasLocalEpisodes
                DetailMoreSheetView(
                    item: detail,
                    hasLocalEpisodes: hasLocalEpisodes,
                    selectedSeasonNumber: detail.mediaType == "series" ? viewModel.selectedSeasonNumber : nil,
                    canDeleteSelectedSeason: detail.mediaType == "series" && hasLocalEpisodes,
                    canReadOverview: detail.preferredOverview != nil,
                    watchedActionTitle: moreWatchedActionTitle(detail),
                    onReadOverview: {
                        pendingMoreAction = .readOverview
                        viewModel.showMoreSheet = false
                    },
                    onToggleWatched: {
                        pendingMoreAction = .toggleWatched
                        viewModel.showMoreSheet = false
                    },
                    onToggleMonitor: {
                        viewModel.showMoreSheet = false
                        Task { await viewModel.toggleMonitor() }
                    },
                    onDeleteSeason: { seasonNum in
                        pendingMoreAction = .deleteSeason(seasonNum)
                        viewModel.showMoreSheet = false
                    },
                    onDeleteTitle: {
                        pendingMoreAction = .deleteTitle
                        viewModel.showMoreSheet = false
                    },
                    onClose: {
                        viewModel.showMoreSheet = false
                    }
                )
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $viewModel.showFullOverviewSheet) {
            if let detail = viewModel.detail, let overview = detail.preferredOverview {
                DetailOverviewSheetView(
                    item: detail,
                    overview: overview,
                    onClose: {
                        viewModel.showFullOverviewSheet = false
                    }
                )
                .preferredColorScheme(.dark)
            }
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

    private func moreWatchedActionTitle(_ detail: TvItemDetail) -> String {
        if detail.watched {
            return "Marker som usett"
        }
        if detail.mediaType == "series", let next = detail.nextUp {
            return "Marker S\(next.season) E\(next.episode) som sett"
        }
        return "Marker som sett"
    }
}
