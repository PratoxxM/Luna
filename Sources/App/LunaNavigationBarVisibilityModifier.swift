import SwiftUI

private struct LunaSubpageVisibilitySinkKey: EnvironmentKey {
    static let defaultValue: LunaSubpageVisibilitySink = .noop
}

private struct LunaScrollToTopNonceKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

private struct LunaContentEntryFocusNonceKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

public extension EnvironmentValues {
    var lunaSubpageVisibility: LunaSubpageVisibilitySink {
        get { self[LunaSubpageVisibilitySinkKey.self] }
        set { self[LunaSubpageVisibilitySinkKey.self] = newValue }
    }

    var lunaScrollToTopNonce: Int {
        get { self[LunaScrollToTopNonceKey.self] }
        set { self[LunaScrollToTopNonceKey.self] = newValue }
    }

    var lunaContentEntryFocusNonce: Int {
        get { self[LunaContentEntryFocusNonceKey.self] }
        set { self[LunaContentEntryFocusNonceKey.self] = newValue }
    }
}

extension View {
    func lunaRootScrollTopBarTracking(tab: MainNavigationTab, isEnabled: Bool = true) -> some View {
        modifier(LunaRootScrollTopBarModifier(tab: tab, isEnabled: isEnabled))
    }
}

private struct LunaRootScrollTopBarModifier: ViewModifier {
    @Environment(\.lunaSubpageVisibility) private var visibilitySink
    let tab: MainNavigationTab
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.onScrollGeometryChange(for: ScrollTopSample.self) { geo in
                ScrollTopSample.capture(scrolledOffsetY: Double(geo.contentOffset.y + geo.contentInsets.top))
            } action: { oldSample, newSample in
                visibilitySink.reportScrollSample(oldSample, newSample, tab)
            }
        } else {
            content
        }
    }
}
