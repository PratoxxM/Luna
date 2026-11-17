import SwiftUI

public enum MainNavigationTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case movies
    case series
    case library
    case search
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Hjem"
        case .movies: return "Filmer"
        case .series: return "Serier"
        case .library: return "Mitt bibliotek"
        case .search: return "Søk"
        case .settings: return "Innstillinger"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "sparkles.tv"
        case .movies: return "film"
        case .series: return "tv"
        case .library: return "books.vertical.fill"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
final class LunaNavigationBarVisibility: ObservableObject {
    @Published private(set) var activeSubpageTokens: Set<UUID> = []

    var isTopBarHidden: Bool {
        !activeSubpageTokens.isEmpty
    }

    var sink: LunaSubpageVisibilitySink {
        LunaSubpageVisibilitySink(
            enterSubpage: { [weak self] token in
                self?.enterSubpage(token)
            },
            leaveSubpage: { [weak self] token in
                self?.leaveSubpage(token)
            }
        )
    }

    func enterSubpage(_ token: UUID) {
        activeSubpageTokens.insert(token)
    }

    func leaveSubpage(_ token: UUID) {
        activeSubpageTokens.remove(token)
    }
}

public struct LunaSubpageVisibilitySink: Sendable {
    public let enterSubpage: @MainActor @Sendable (UUID) -> Void
    public let leaveSubpage: @MainActor @Sendable (UUID) -> Void

    public static let noop = LunaSubpageVisibilitySink(
        enterSubpage: { _ in },
        leaveSubpage: { _ in }
    )
}

private struct LunaSubpageVisibilitySinkKey: EnvironmentKey {
    static let defaultValue: LunaSubpageVisibilitySink = .noop
}

public extension EnvironmentValues {
    var lunaSubpageVisibility: LunaSubpageVisibilitySink {
        get { self[LunaSubpageVisibilitySinkKey.self] }
        set { self[LunaSubpageVisibilitySinkKey.self] = newValue }
    }
}

struct LunaTopBarView: View {
    static let contentTopPadding: CGFloat = 94

    @Binding var selectedTab: MainNavigationTab
    let showCatCompanions: Bool
    let roomBadge: String?

    @FocusState private var focusedTab: MainNavigationTab?
    @State private var wasBarFocused: Bool = false
    @Namespace private var topBarFocusNamespace

    var body: some View {
        HStack(spacing: 20) {
            emblemView

            HStack(spacing: 10) {
                ForEach(MainNavigationTab.allCases) { tab in
                    TopBarTabPillButton(
                        tab: tab,
                        isActive: selectedTab == tab,
                        isFocused: focusedTab == tab
                    ) {
                        selectedTab = tab
                        focusedTab = tab
                    }
                    .focused($focusedTab, equals: tab)
                    .prefersDefaultFocus(selectedTab == tab, in: topBarFocusNamespace)
                }
            }

            Spacer(minLength: 16)

            if let roomBadge, !roomBadge.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "tv.and.hifispeaker.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LunaTheme.amber.opacity(0.90))
                    Text(roomBadge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LunaTheme.moonlight.opacity(0.88))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LunaTheme.buttonSubtleGradient)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(LunaTheme.moonlight.opacity(0.20), lineWidth: 1)
                )
                .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(dockBackground)
        .overlay(
            Capsule()
                .strokeBorder(LunaTheme.topInnerHighlightGradient(isFocused: false), lineWidth: 1.0)
        )
        .overlay(
            Capsule()
                .strokeBorder(LunaTheme.moonlight.opacity(0.22), lineWidth: 1.1)
        )
        .shadow(color: Color.black.opacity(0.62), radius: 22, x: 0, y: 10)
        .padding(.horizontal, LunaTheme.horizontalGutter)
        .padding(.top, 4)
        .focusScope(topBarFocusNamespace)
        .focusSection()
        .onChange(of: focusedTab) { _, newFocus in
            guard let newTab = newFocus else {
                wasBarFocused = false
                return
            }
            if !wasBarFocused {
                wasBarFocused = true
                if newTab != selectedTab {
                    focusedTab = selectedTab
                }
            } else if selectedTab != newTab {
                selectedTab = newTab
            }
        }
    }

    private var emblemView: some View {
        HStack(spacing: 10) {
            Image(showCatCompanions ? "LunaMoonCatsEmblem" : "LunaMoonCrescent")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .shadow(color: LunaTheme.amber.opacity(0.34), radius: 8, x: 0, y: 1)

            Text("Luna")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.trailing, 8)
        .allowsHitTesting(false)
    }

    private var dockBackground: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 17.0 / 255.0, green: 24.0 / 255.0, blue: 40.0 / 255.0).opacity(0.94),
                        Color(red: 10.0 / 255.0, green: 14.0 / 255.0, blue: 24.0 / 255.0).opacity(0.96),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

private struct TopBarTabPillButton: View {
    let tab: MainNavigationTab
    let isActive: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(iconColor)

                Text(tab.title)
                    .font(.system(size: 23, weight: isActive || isFocused ? .bold : .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(pillBackground)
            .overlay(
                Capsule()
                    .strokeBorder(LunaTheme.topInnerHighlightGradient(isFocused: isFocused), lineWidth: 1.0)
            )
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: isFocused ? 2.3 : (isActive ? 1.75 : 1.0))
            )
            .overlay(alignment: .bottom) {
                if isActive && !isFocused {
                    Capsule()
                        .fill(LunaTheme.amber)
                        .frame(width: 24, height: 3)
                        .offset(y: -3)
                }
            }
            .shadow(
                color: shadowColor,
                radius: isFocused ? 18 : (isActive ? 12 : 4),
                x: 0,
                y: isFocused ? 7 : 3
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isFocused)
            .animation(.easeOut(duration: 0.16), value: isActive)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(Capsule())
        .focusEffectDisabled(true)
    }

    private var iconColor: Color {
        if isFocused { return LunaTheme.canvas }
        if isActive { return LunaTheme.amber }
        return LunaTheme.moonlight.opacity(0.88)
    }

    private var textColor: Color {
        if isFocused { return LunaTheme.canvas }
        if isActive { return .white }
        return LunaTheme.moonlight.opacity(0.92)
    }

    @ViewBuilder
    private var pillBackground: some View {
        if isFocused {
            Capsule().fill(LunaTheme.focusGoldGradient)
        } else if isActive {
            ZStack {
                Capsule().fill(LunaTheme.buttonSelectedBaseGradient)
                Capsule().fill(LunaTheme.amber.opacity(0.30))
            }
        } else {
            Capsule().fill(LunaTheme.buttonSubtleGradient)
        }
    }

    private var borderColor: Color {
        if isFocused { return LunaTheme.focusGoldBorder }
        if isActive { return LunaTheme.amber.opacity(0.92) }
        return LunaTheme.moonlight.opacity(0.24)
    }

    private var shadowColor: Color {
        if isFocused { return LunaTheme.amber.opacity(0.55) }
        if isActive { return LunaTheme.amber.opacity(0.28) }
        return Color.black.opacity(0.25)
    }
}
