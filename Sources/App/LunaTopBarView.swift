import SwiftUI
import UIKit

struct LunaTopBarView: View {
    static let contentTopPadding: CGFloat = 162
    static let focusDebounceNanoseconds: UInt64 = 180_000_000

    @Environment(\.lunaRoomAtmosphere) private var environmentAtmosphere

    @Binding var selectedTab: MainNavigationTab
    var roomName: String? = nil
    var focusRequestNonce: Int = 0
    var isUpwardBridgeEnabled: Bool = false
    var onFocusPresenceChanged: (Bool) -> Void = { _ in }
    var onRequestDownwardContentFocus: (MainNavigationTab) -> Void = { _ in }

    @FocusState private var focusedTab: MainNavigationTab?
    @State private var wasBarFocused: Bool = false
    @State private var lastHighlightedTab: MainNavigationTab
    @State private var tabDebounceTask: Task<Void, Never>?
    @State private var focusRetryTask: Task<Void, Never>?
    @Namespace private var topBarFocusNamespace

    init(
        selectedTab: Binding<MainNavigationTab>,
        roomName: String? = nil,
        focusRequestNonce: Int = 0,
        isUpwardBridgeEnabled: Bool = false,
        onFocusPresenceChanged: @escaping (Bool) -> Void = { _ in },
        onRequestDownwardContentFocus: @escaping (MainNavigationTab) -> Void = { _ in }
    ) {
        self._selectedTab = selectedTab
        self.roomName = roomName
        self.focusRequestNonce = focusRequestNonce
        self.isUpwardBridgeEnabled = isUpwardBridgeEnabled
        self.onFocusPresenceChanged = onFocusPresenceChanged
        self.onRequestDownwardContentFocus = onRequestDownwardContentFocus
        self._lastHighlightedTab = State(initialValue: selectedTab.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                emblemView

                Rectangle()
                    .fill(LunaTheme.warmBorderStrong)
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    ForEach(MainNavigationTab.primaryTabs) { tab in
                        tabButton(for: tab, isIconOnly: false)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 32)

                HStack(spacing: 10) {
                    ForEach(MainNavigationTab.utilityTabs) { tab in
                        tabButton(for: tab, isIconOnly: true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 46)
            .padding(.bottom, 14)
            .defaultFocus($focusedTab, selectedTab as MainNavigationTab?, priority: .automatic)
            .focusScope(topBarFocusNamespace)
            .focusSection()

            // Full-width 1920 pt bidirectional-safe focus bridges with mutually exclusive activation:
            // - Downward bridge fires when leaving top bar downward: commits any in-flight debounce tab
            //   and routes focus deterministically to the left-aligned x=90 entry target on the page.
            // - Upward bridge fires when content presses Up: returns focus straight to selectedTab.
            ZStack {
                TopBarFocusBridge(
                    isEnabled: focusedTab != nil,
                    cooldownSeconds: 0.14
                ) {
                    routeDownwardToContent()
                }

                TopBarFocusBridge(
                    isEnabled: isUpwardBridgeEnabled && focusedTab == nil,
                    cooldownSeconds: 0.12
                ) {
                    redirectFocusToSelectedTab()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            .focusEffectDisabled(true)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
        .onChange(of: selectedTab) { _, newTab in
            lastHighlightedTab = newTab
        }
        .onChange(of: focusedTab) { _, newFocus in
            onFocusPresenceChanged(newFocus != nil)
            guard let newTab = newFocus else {
                wasBarFocused = false
                tabDebounceTask?.cancel()
                tabDebounceTask = nil
                return
            }
            wasBarFocused = true
            lastHighlightedTab = newTab
            tabDebounceTask?.cancel()
            guard selectedTab != newTab else {
                tabDebounceTask = nil
                return
            }
            let debounceNs = Self.focusDebounceNanoseconds
            tabDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: debounceNs)
                guard !Task.isCancelled, wasBarFocused, focusedTab == newTab else { return }
                if selectedTab != newTab {
                    selectedTab = newTab
                }
            }
        }
        .onChange(of: focusRequestNonce) { _, _ in
            redirectFocusToSelectedTab()
        }
        .onAppear {
            wasBarFocused = (focusedTab != nil)
            lastHighlightedTab = focusedTab ?? selectedTab
            onFocusPresenceChanged(focusedTab != nil)
        }
        .onDisappear {
            wasBarFocused = false
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
            focusRetryTask?.cancel()
            focusRetryTask = nil
        }
    }

    private func routeDownwardToContent() {
        tabDebounceTask?.cancel()
        tabDebounceTask = nil
        let target = focusedTab ?? lastHighlightedTab
        if selectedTab != target {
            selectedTab = target
        }
        focusedTab = nil
        wasBarFocused = false
        onRequestDownwardContentFocus(target)
    }

    private func redirectFocusToSelectedTab() {
        tabDebounceTask?.cancel()
        tabDebounceTask = nil
        focusRetryTask?.cancel()
        let target = selectedTab
        focusedTab = target
        lastHighlightedTab = target
        focusRetryTask = Task { @MainActor in
            for delayNs: UInt64 in [16_000_000, 44_000_000, 72_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, selectedTab == target else { return }
                if focusedTab == nil {
                    focusedTab = target
                } else {
                    return
                }
            }
        }
    }

    @ViewBuilder
    private func tabButton(for tab: MainNavigationTab, isIconOnly: Bool) -> some View {
        TopBarTabPillButton(
            tab: tab,
            isActive: selectedTab == tab,
            isFocused: focusedTab == tab,
            isBarFocused: focusedTab != nil,
            isIconOnly: isIconOnly
        ) {
            tabDebounceTask?.cancel()
            tabDebounceTask = nil
            if selectedTab != tab {
                selectedTab = tab
            }
            lastHighlightedTab = tab
            focusedTab = tab
        }
        .focused($focusedTab, equals: tab)
        .prefersDefaultFocus(selectedTab == tab, in: topBarFocusNamespace)
    }

    private var emblemView: some View {
        let displayLabel: String = {
            let trimmed = (roomName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Luna" : trimmed
        }()

        return HStack(spacing: 14) {
            LunaCrescentMarkView(size: 34, color: LunaTheme.amber)

            Text(displayLabel)
                .font(LunaTheme.Font.brandSerif)
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .allowsHitTesting(false)
    }
}

struct TopBarTabPillButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let tab: MainNavigationTab
    let isActive: Bool
    let isFocused: Bool
    var isBarFocused: Bool = false
    var isIconOnly: Bool = false
    let action: () -> Void

    nonisolated static let utilityButtonSize: CGFloat = 56
    nonisolated static let restingIndicatorWidth: CGFloat = 22
    nonisolated static let restingIndicatorHeight: CGFloat = 2.5

    nonisolated static func shouldShowRestingActiveIndicator(
        isActive: Bool,
        isFocused: Bool,
        isBarFocused: Bool = false
    ) -> Bool {
        isActive && !isFocused && !isBarFocused
    }

    nonisolated static func resolveIconColor(
        isActive: Bool,
        isFocused: Bool,
        isBarFocused: Bool = false
    ) -> Color {
        if isFocused { return LunaTheme.linen }
        if isActive && !isBarFocused { return LunaTheme.linen }
        return LunaTheme.muted
    }

    nonisolated static func resolveTextColor(
        isActive: Bool,
        isFocused: Bool,
        isBarFocused: Bool = false
    ) -> Color {
        if isFocused { return LunaTheme.linen }
        if isActive && !isBarFocused { return LunaTheme.linen }
        return LunaTheme.muted
    }

    nonisolated static func resolveBorderColor(
        isActive: Bool,
        isFocused: Bool,
        isBarFocused: Bool = false
    ) -> Color {
        if isFocused {
            return LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity)
        }
        return Color.clear
    }

    var body: some View {
        let showRestingBar = Self.shouldShowRestingActiveIndicator(
            isActive: isActive,
            isFocused: isFocused,
            isBarFocused: isBarFocused
        )

        Button(action: action) {
            Group {
                if isIconOnly {
                    Image(systemName: tab.systemImage)
                        .font(LunaTheme.Font.tabIcon)
                        .foregroundStyle(
                            Self.resolveIconColor(
                                isActive: isActive,
                                isFocused: isFocused,
                                isBarFocused: isBarFocused
                            )
                        )
                        .frame(width: Self.utilityButtonSize, height: Self.utilityButtonSize)
                } else {
                    Text(tab.title)
                        .font(LunaTheme.Font.tabTitle)
                        .foregroundStyle(
                            Self.resolveTextColor(
                                isActive: isActive,
                                isFocused: isFocused,
                                isBarFocused: isBarFocused
                            )
                        )
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                        .frame(height: Self.utilityButtonSize)
                }
            }
            .transaction { $0.animation = nil }
            .background(
                Capsule()
                    .fill(LunaTheme.surfaceElevated)
                    .opacity(isFocused ? 1 : 0)
                    .transaction { $0.animation = nil }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        Self.resolveBorderColor(
                            isActive: isActive,
                            isFocused: isFocused,
                            isBarFocused: isBarFocused
                        ),
                        lineWidth: LunaFocusStyle.borderWidth
                    )
                    .transaction { $0.animation = nil }
            )
            .overlay(alignment: .bottom) {
                if showRestingBar {
                    Capsule()
                        .fill(LunaTheme.amber)
                        .frame(width: Self.restingIndicatorWidth, height: Self.restingIndicatorHeight)
                        .padding(.bottom, 5)
                        .allowsHitTesting(false)
                        .transaction { $0.animation = nil }
                }
            }
            .shadow(
                color: isFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength) : .clear,
                radius: isFocused ? 24 : 0,
                x: 0,
                y: isFocused ? 10 : 0
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(reduceMotion ? .linear(duration: 0.01) : LunaFocusStyle.focusSpring, value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
        .accessibilityLabel(tab.title)
    }
}

@MainActor
private struct TopBarFocusBridge: UIViewRepresentable {
    let isEnabled: Bool
    let cooldownSeconds: TimeInterval
    let onRedirect: () -> Void

    func makeUIView(context: Context) -> TopBarFocusBridgeUIView {
        let view = TopBarFocusBridgeUIView()
        view.isBridgeEnabled = isEnabled
        view.cooldownSeconds = cooldownSeconds
        view.onRedirect = onRedirect
        return view
    }

    func updateUIView(_ uiView: TopBarFocusBridgeUIView, context: Context) {
        uiView.isBridgeEnabled = isEnabled
        uiView.cooldownSeconds = cooldownSeconds
        uiView.onRedirect = onRedirect
    }
}

@MainActor
private final class TopBarFocusBridgeUIView: UIView {
    var isBridgeEnabled: Bool = false
    var cooldownSeconds: TimeInterval = 0.12
    var onRedirect: (() -> Void)?
    private var isBouncing: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }

    override var canBecomeFocused: Bool {
        isBridgeEnabled && !isBouncing
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard context.nextFocusedView === self else { return }
        isBouncing = true
        DispatchQueue.main.async { [weak self] in
            self?.onRedirect?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + cooldownSeconds) { [weak self] in
            self?.isBouncing = false
        }
    }
}
