import SwiftUI

/// Debounced ambient focus backdrop state.
///
/// Delays updates by `400 ms` so fast Siri Remote scrolling across rows cancels
/// intermediate transitions and performs 0 backdrop renders until focus settles.
@MainActor
public final class AmbientBackdropController: ObservableObject {
    @Published public private(set) var dominantHex: String?
    @Published public private(set) var backdropURL: URL?
    @Published public private(set) var blurHash: String?

    private var debounceTask: Task<Void, Never>?

    public init() {}

    public func reportFocus(dominantColor: String?, backdropURL: URL?, blurHash: String?) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.dominantHex == dominantColor && self.backdropURL == backdropURL {
                return
            }
            withAnimation(.easeOut(duration: 0.42)) {
                self.dominantHex = dominantColor
                self.backdropURL = backdropURL
                self.blurHash = blurHash
            }
        }
    }

    public func setImmediate(dominantColor: String?, backdropURL: URL?, blurHash: String?) {
        debounceTask?.cancel()
        withAnimation(.easeOut(duration: 0.30)) {
            self.dominantHex = dominantColor
            self.backdropURL = backdropURL
            self.blurHash = blurHash
        }
    }
}

public struct AmbientBackdropView: View {
    @ObservedObject var controller: AmbientBackdropController
    let client: MediaOSClient?

    public init(controller: AmbientBackdropController, client: MediaOSClient?) {
        self.controller = controller
        self.client = client
    }

    public var body: some View {
        let glowColor = LunaTheme.color(fromHex: controller.dominantHex) ?? Color(red: 0.13, green: 0.17, blue: 0.27)

        ZStack {
            LunaTheme.canvas

            if let url = controller.backdropURL {
                CachedArtworkView(
                    url: url,
                    client: client,
                    maxPixelSize: 640,
                    blurHash: controller.blurHash,
                    dominantColor: controller.dominantHex,
                    placeholderSymbol: "sparkles.tv",
                    contentMode: .fill
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 76)
                .opacity(0.17)
                .id(url)
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
    }
}
