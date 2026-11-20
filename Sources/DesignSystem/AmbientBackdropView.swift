import SwiftUI
import UIKit

extension LunaTheme {
    /// Exact `#0A0908` UIKit color matching `LunaTheme.canvas` for `UINavigationController` / `UIHostingController`.
    public nonisolated static var canvasUIColor: UIColor {
        UIColor(red: 10.0 / 255.0, green: 9.0 / 255.0, blue: 8.0 / 255.0, alpha: 1.0)
    }
}

/// Static, calm LunaCore menu canvas: near-black warm charcoal (`#0A0908`) with a subtle
/// top warm candlelight shimmer — zero shifting poster colors or BlurHash crossfades during scrolling,
/// and paused down to a single flat layer whenever full-screen video playback is active.
public struct AmbientBackdropView: View {
    @Environment(\.lunaRoomAtmosphere) private var environmentAtmosphere

    public var isPaused: Bool
    public var atmosphere: LunaRoomAtmosphere?

    public init(isPaused: Bool = false, atmosphere: LunaRoomAtmosphere? = nil) {
        self.isPaused = isPaused
        self.atmosphere = atmosphere
    }

    private var activeAtmosphere: LunaRoomAtmosphere {
        atmosphere ?? environmentAtmosphere
    }

    public var body: some View {
        let room = activeAtmosphere

        ZStack {
            LunaTheme.canvas

            if !isPaused {
                // Subtle warm espresso depth at the top matching M0 canvas-glow
                LinearGradient(
                    stops: [
                        .init(color: LunaTheme.surface.opacity(0.76), location: 0.0),
                        .init(color: LunaTheme.surface.opacity(0.24), location: 0.34),
                        .init(color: .clear, location: 0.68),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Soft fixed candlelight glow (~5.5–6 % amber) without washed-out gray/slate cast
                RadialGradient(
                    colors: [
                        LunaTheme.amber.opacity(room.ambientOpacity),
                        LunaTheme.amberDeep.opacity(room.ambientOpacity * 0.38),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.50, y: -0.06),
                    startRadius: 20,
                    endRadius: 860
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

internal enum NavigationContainerBackdropMode {
    case ambient(isPaused: Bool)
    case probeOnly
}

@MainActor
internal enum UIKitNavigationBackdropApplier {
    static func apply(from controller: UIViewController, color: UIColor) {
        var cursor = controller.parent
        while let ancestor = cursor {
            if ancestor.viewIfLoaded?.backgroundColor != color {
                ancestor.viewIfLoaded?.backgroundColor = color
            }
            if let nav = ancestor as? UINavigationController {
                applyNavigationController(nav, color: color)
            }
            if let tab = ancestor as? UITabBarController {
                applyTabBarController(tab, color: color)
            }
            cursor = ancestor.parent
        }
        if let nav = controller.navigationController {
            applyNavigationController(nav, color: color)
        }
        if let tab = controller.tabBarController {
            applyTabBarController(tab, color: color)
        }
        if let window = controller.viewIfLoaded?.window, window.backgroundColor != color {
            window.backgroundColor = color
        }
    }

    static func applyNavigationController(_ nav: UINavigationController, color: UIColor) {
        if nav.viewIfLoaded?.backgroundColor != color {
            nav.viewIfLoaded?.backgroundColor = color
        }
        for childVC in nav.viewControllers {
            if childVC.viewIfLoaded?.backgroundColor != color {
                childVC.viewIfLoaded?.backgroundColor = color
            }
        }
        if let navView = nav.viewIfLoaded {
            applyTransitionContainerViews(in: navView, depth: 0, color: color)
        }
    }

    static func applyTabBarController(_ tab: UITabBarController, color: UIColor) {
        if tab.viewIfLoaded?.backgroundColor != color {
            tab.viewIfLoaded?.backgroundColor = color
        }
        for childVC in tab.viewControllers ?? [] {
            if childVC.viewIfLoaded?.backgroundColor != color {
                childVC.viewIfLoaded?.backgroundColor = color
            }
            if let childNav = childVC as? UINavigationController {
                applyNavigationController(childNav, color: color)
            }
        }
    }

    private static func applyTransitionContainerViews(in view: UIView, depth: Int, color: UIColor) {
        guard depth < 2 else { return }
        for subview in view.subviews {
            if subview is UINavigationBar {
                continue
            }
            let className = NSStringFromClass(type(of: subview))
            if className.contains("TransitionView") || className.contains("WrapperView") {
                if subview.backgroundColor != color {
                    subview.backgroundColor = color
                }
            }
            applyTransitionContainerViews(in: subview, depth: depth + 1, color: color)
        }
    }
}

internal final class NonFocusableBackdropProbeView: UIView {
    var onMoveToWindow: (() -> Void)?

    override var canBecomeFocused: Bool { false }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onMoveToWindow?()
        }
    }
}

internal final class BackdropInstallerViewController: UIViewController {
    private var backdropColor: UIColor

    init(backgroundColor: UIColor) {
        self.backdropColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let probeView = NonFocusableBackdropProbeView(frame: .zero)
        probeView.backgroundColor = .clear
        probeView.isOpaque = false
        probeView.isUserInteractionEnabled = false
        probeView.onMoveToWindow = { [weak self] in
            self?.installContainerBackdrops()
        }
        view = probeView
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        installContainerBackdrops()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installContainerBackdrops()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installContainerBackdrops()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installContainerBackdrops()
    }

    func applyBackdropColor(_ color: UIColor) {
        backdropColor = color
        installContainerBackdrops()
    }

    private func installContainerBackdrops() {
        UIKitNavigationBackdropApplier.apply(from: self, color: backdropColor)
    }
}

internal struct NavigationContainerBackdropProbe: UIViewControllerRepresentable {
    let backgroundColor: UIColor

    func makeUIViewController(context: Context) -> BackdropInstallerViewController {
        BackdropInstallerViewController(backgroundColor: backgroundColor)
    }

    func updateUIViewController(_ uiViewController: BackdropInstallerViewController, context: Context) {
        uiViewController.applyBackdropColor(backgroundColor)
    }
}

internal struct LunaNavigationContainerBackdropModifier: ViewModifier {
    let isEnabled: Bool
    let mode: NavigationContainerBackdropMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            switch mode {
            case .ambient(let isPaused):
                ZStack(alignment: .topLeading) {
                    AmbientBackdropView(isPaused: isPaused)
                    NavigationContainerBackdropProbe(backgroundColor: LunaTheme.canvasUIColor)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    content
                }
            case .probeOnly:
                content.background {
                    NavigationContainerBackdropProbe(backgroundColor: LunaTheme.canvasUIColor)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// tvOS SDK marks `ContainerBackgroundPlacement.navigation` & `.tabView` unavailable, so
    /// each view inside `NavigationStack` pairs a full-bleed SwiftUI backdrop with a non-focusable
    /// UIKit probe that paints the enclosing `UIHostingController`, `UINavigationController`,
    /// `UITabBarController`, transition container, and `UIWindow` to `#0A0908` (`LunaTheme.canvas`).
    @MainActor
    func lunaNavigationContainerBackdrop(
        isEnabled: Bool = true,
        mode: NavigationContainerBackdropMode
    ) -> some View {
        modifier(LunaNavigationContainerBackdropModifier(isEnabled: isEnabled, mode: mode))
    }
}
