import SwiftUI

public struct GenreTileView: View {
    let chip: TvGenreChip
    let onSelect: () -> Void

    @FocusState private var isFocused: Bool

    public init(chip: TvGenreChip, onSelect: @escaping () -> Void) {
        self.chip = chip
        self.onSelect = onSelect
    }

    public var body: some View {
        let accent = LunaTheme.color(fromHex: chip.accentColor) ?? LunaTheme.amber
        let symbol = LunaTheme.symbolForGenre(slug: chip.slug, serverIcon: chip.icon)

        Button(action: onSelect) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(isFocused ? 0.42 : 0.24),
                                LunaTheme.surfaceRaised,
                                LunaTheme.surface
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: symbol)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(isFocused ? .white : accent)
                            .frame(width: 44, height: 44)
                            .background(accent.opacity(0.18), in: Circle())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(LunaTheme.moonlight.opacity(isFocused ? 0.9 : 0.35))
                    }

                    Spacer(minLength: 4)

                    Text(chip.label)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(20)
            }
            .frame(width: 264, height: 136)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.card)
        .focused($isFocused)
    }
}
