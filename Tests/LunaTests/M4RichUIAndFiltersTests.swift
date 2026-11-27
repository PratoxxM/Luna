import Foundation
import SwiftUI
import XCTest
@testable import Luna

final class M4RichUIAndFiltersTests: XCTestCase {
    @MainActor
    func testHomeViewEffectiveDisplayRowsAndTonightReasonLabel() {
        let basePayload = PreviewMockFixtures.homeResponse
        let rows = HomeView.prepareVisibleRows(from: basePayload)
        XCTAssertEqual(HomeView.effectiveDisplayRows(rows: rows, tonight: basePayload.tonight).count, rows.count)

        let spotlightCard = PreviewMockFixtures.dunePartTwoCard
        let coldTonight = TvTonightPayload(
            ok: true,
            reason: "new_on_nvme",
            reasonLabel: "Nytt på NVMe · Starter umiddelbart",
            item: spotlightCard
        )
        let nonContinueRows = rows.filter {
            $0.rowId != "medialogg-continue" && $0.sourceKind != "system_continue"
        }
        let augmented = HomeView.effectiveDisplayRows(rows: nonContinueRows, tonight: coldTonight)
        XCTAssertEqual(augmented.first?.rowId, "tonight-spotlight")
        XCTAssertEqual(augmented.first?.title, "I kveld")
        XCTAssertEqual(augmented.first?.items.first?.itemId, spotlightCard.itemId)

        let homeVM = HomeViewModel()
        let homeView = HomeView(viewModel: homeVM)
        _ = homeView
        let shelf = ShelfRowView(
            row: augmented[0],
            tonightReasonLabel: coldTonight.reasonLabel,
            isDefaultFocusRow: true,
            mountedTracker: MountedEntryCardTracker(),
            entryCardKey: nil,
            entryFocusNonce: 0,
            focusNamespace: Namespace().wrappedValue,
            client: nil,
            onSelectCard: { _ in },
            onPlayContinueCard: { _ in },
            onPickSourceForCard: { _ in },
            onToggleWatchlist: { _ in },
            onMarkWatched: { _ in },
            onRemoveFromOngoing: { _ in },
            onRemoveFromList: { _, _ in },
            onSeeAllRow: { _ in }
        )
        XCTAssertEqual(shelf.tonightReasonLabel, "Nytt på NVMe · Starter umiddelbart")
    }

    @MainActor
    func testLibraryHubAndSearchViewsBindTierSortAndKindFilters() {
        let libVM = LibraryViewModel()
        libVM.selectedTier = .nvme
        libVM.selectedSort = .rating
        XCTAssertTrue(libVM.supportsTierAndSortFilters)
        libVM.activeSection = .watchlist
        XCTAssertFalse(libVM.supportsTierAndSortFilters)

        let libHub = LibraryHubView(viewModel: libVM, isActiveTab: true)
        _ = libHub

        let searchVM = SearchViewModel(initialQuery: "Dune", isRootTab: true)
        searchVM.selectedKind = .series
        XCTAssertEqual(TvSearchKindFilter.allCases.map(\.label), ["Alle", "Filmer", "Serier"])
        let searchView = SearchView(viewModel: searchVM, initialQuery: "Dune", isRootTab: true)
        XCTAssertTrue(searchView.isRootTab)
    }

    @MainActor
    func testSourceCandidateRowViewSurfacesExplanationChipsAndReleaseGroup() {
        let candidate = TvCandidateInfo(
            candidateId: "cand-framestor",
            displayHeadline: "4K · Remux · Dolby Vision P7 FEL",
            releaseTitle: "Dune.Part.Two.2024.2160p.REMUX-FraMeSToR",
            source: "nvme",
            tier: "nvme",
            resolution: "2160p",
            videoRangeType: "Dolby Vision",
            dvProfile: 7,
            dvEnhancementLayer: "FEL",
            audioCodec: "TrueHD Atmos",
            sizeBytes: 77_738_909_696,
            tvScore: 1280,
            isActive: true,
            explanationChips: ["På NVMe", "DV P7 FEL", "TrueHD Atmos", "DV P7 FEL"],
            releaseGroup: "FraMeSToR",
            isNorwegian: true,
            videoCodec: "hevc",
            sourceQuality: "Bluray-2160p"
        )

        let richFull = candidate.richRowSubtitle(
            isRecommended: true,
            activeLabel: "Forhåndsvalgt",
            compactForQuickPanel: false
        )
        XCTAssertTrue(richFull.contains("FraMeSToR"))
        XCTAssertTrue(richFull.contains("DV P7 FEL"))
        XCTAssertTrue(richFull.contains("TrueHD Atmos"))
        XCTAssertFalse(richFull.contains("På NVMe · På NVMe"))

        let richCompact = candidate.richRowSubtitle(
            isRecommended: false,
            activeLabel: nil,
            compactForQuickPanel: true
        )
        XCTAssertTrue(richCompact.contains("FraMeSToR"))
        XCTAssertTrue(richCompact.contains("DV P7 FEL"))

        let row = SourceCandidateRowView(
            candidate: candidate,
            isRecommended: true,
            isSelected: true,
            activeStatusLabel: "Spilles nå",
            isFocused: true,
            compactForQuickPanel: false
        ) {}
        XCTAssertEqual(row.candidate.releaseGroup, "FraMeSToR")
        XCTAssertEqual(row.candidate.explanationChips?.count, 4)
    }
}
