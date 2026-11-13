import SwiftUI

/// Lightweight focus-reporting closure bag so focused cards and detail views
/// never subscribe to `AmbientBackdropController`'s `@Published` properties.
public struct AmbientFocusSink: Sendable {
    public let reportFocus: @MainActor @Sendable (String?, URL?, String?) -> Void
    public let setImmediate: @MainActor @Sendable (String?, URL?, String?) -> Void

    public static let noop = AmbientFocusSink(
        reportFocus: { _, _, _ in },
        setImmediate: { _, _, _ in }
    )
}

private struct AmbientFocusSinkKey: EnvironmentKey {
    static let defaultValue: AmbientFocusSink = .noop
}

public extension EnvironmentValues {
    var ambientFocusSink: AmbientFocusSink {
        get { self[AmbientFocusSinkKey.self] }
        set { self[AmbientFocusSinkKey.self] = newValue }
    }
}

/// Debounced ambient focus backdrop state.
///
/// Delays updates by `400 ms` so fast Siri Remote scrolling across rows cancels
/// intermediate transitions and performs 0 backdrop renders until focus settles.
@MainActor
public final class AmbientBackdropController: ObservableObject {
    @Published public private(set) var dominantHex: String?
    @Published public private(set) var blurHash: String?

    private var debounceTask: Task<Void, Never>?

    public init() {}

    public var focusSink: AmbientFocusSink {
        AmbientFocusSink(
            reportFocus: { [weak self] dominantColor, backdropURL, blurHash in
                self?.reportFocus(dominantColor: dominantColor, backdropURL: backdropURL, blurHash: blurHash)
            },
            setImmediate: { [weak self] dominantColor, backdropURL, blurHash in
                self?.setImmediate(dominantColor: dominantColor, backdropURL: backdropURL, blurHash: blurHash)
            }
        )
    }

    public func reportFocus(dominantColor: String?, backdropURL: URL? = nil, blurHash: String?) {
        _ = backdropURL
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.dominantHex == dominantColor && self.blurHash == blurHash {
                return
            }
            withAnimation(.easeOut(duration: 0.42)) {
                self.dominantHex = dominantColor
                self.blurHash = blurHash
            }
        }
    }

    public func setImmediate(dominantColor: String?, backdropURL: URL? = nil, blurHash: String?) {
        _ = backdropURL
        debounceTask?.cancel()
        withAnimation(.easeOut(duration: 0.30)) {
            self.dominantHex = dominantColor
            self.blurHash = blurHash
        }
    }
}

public struct AmbientBackdropView: View {
    @ObservedObject var controller: AmbientBackdropController

    @State private var decodedBlurImage: CGImage?

    public init(controller: AmbientBackdropController) {
        self.controller = controller
        _decodedBlurImage = State(initialValue: BlurHashDecoder.cachedImage(controller.blurHash, width: 32, height: 18))
    }

    public var body: some View {
        let glowColor = LunaTheme.color(fromHex: controller.dominantHex) ?? Color(red: 0.13, green: 0.17, blue: 0.27)

        ZStack {
            LunaTheme.canvas

            if let cgImage = decodedBlurImage ?? BlurHashDecoder.cachedImage(controller.blurHash, width: 32, height: 18) {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.22)
                    .transition(.opacity)
            }

            RadialGradient(
                colors: [
                    glowColor.opacity(0.30),
                    glowColor.opacity(0.10),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 60,
                endRadius: 1180
            )

            LinearGradient(
                colors: [
                    LunaTheme.canvas.opacity(0.32),
                    LunaTheme.canvas.opacity(0.76),
                    LunaTheme.canvas
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: controller.blurHash) {
            if let hit = BlurHashDecoder.cachedImage(controller.blurHash, width: 32, height: 18) {
                decodedBlurImage = hit
                return
            }
            let decoded = await BlurHashDecoder.decodeAsync(controller.blurHash, width: 32, height: 18)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.35)) {
                    decodedBlurImage = decoded
                }
            }
        }
    }
}
