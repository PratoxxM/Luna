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

    @FocusState private var focusedTab: MainNavigationTab?
    @State private var wasBarFocused: Bool = false
    @State private var tabDebounceTask: Task<Void, Never>?
    @State private var focusRetryTask: Task<Void, Never>?
    @Namespace private var topBarFocusNamespace

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                emblemView
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    ForEach(MainNavigationTab.primaryTabs) { tab in
                        tabButton(for: tab, isIconOnly: false)
                    }

                    Rectangle()
                        .fill(LunaTheme.warmBorderStrong)
                        .frame(width: 1, height: 28)
                        .padding(.horizontal, 6)
                        .allowsHitTesting(false)

                    ForEach(MainNavigationTab.utilityTabs) { tab in
                        tabButton(for: tab, isIconOnly: true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Color.clear
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .trailing)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LunaTheme.horizontalGutter)
            .padding(.top, 46)
            .padding(.bottom, 14)
            .defaultFocus($focusedTab, selectedTab as MainNavigationTab?, priority: .automatic)
            .focusScope(topBarFocusNamespace)
            .focusSection()

            // Full-width 1920 pt upward-only trampoline active solely when content is focused,
            // guaranteeing pressing Up from left-edge controls never misses the centered dock.
            TopBarUpwardFocusBridge(isEnabled: isUpwardBridgeEnabled && focusedTab == nil) {
                redirectFocusToSelectedTab()
            }
            .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            .focusEffectDisabled(true)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
        .onChange(of: focusedTab) { _, newFocus in
            onFocusPresenceChanged(newFocus != nil)
            guard let newTab = newFocus else {
                wasBarFocused = false
                tabDebounceTask?.cancel()
                tabDebounceTask = nil
                return
            }
            wasBarFocused = true
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

    private func redirectFocusToSelectedTab() {
        tabDebounceTask?.cancel()
        tabDebounceTask = nil
        focusRetryTask?.cancel()
        let target = selectedTab
        focusedTab = target
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
            LunaCrescentMarkView(size: 36, color: LunaTheme.amber)

            Text(displayLabel)
                .font(LunaTheme.Font.brandSerif)
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
        }
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
                        .frame(width: 64, height: 64)
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
                        .padding(.horizontal, 26)
                        .frame(height: 64)
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
private struct TopBarUpwardFocusBridge: UIViewRepresentable {
    let isEnabled: Bool
    let onRedirectUp: () -> Void

    func makeUIView(context: Context) -> TopBarUpwardFocusBridgeUIView {
        let view = TopBarUpwardFocusBridgeUIView()
        view.isBridgeEnabled = isEnabled
        view.onRedirectUp = onRedirectUp
        return view
    }

    func updateUIView(_ uiView: TopBarUpwardFocusBridgeUIView, context: Context) {
        uiView.isBridgeEnabled = isEnabled
        uiView.onRedirectUp = onRedirectUp
    }
}

@MainActor
private final class TopBarUpwardFocusBridgeUIView: UIView {
    var isBridgeEnabled: Bool = false
    var onRedirectUp: (() -> Void)?
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
            self?.onRedirectUp?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.isBouncing = false
        }
    }
}
