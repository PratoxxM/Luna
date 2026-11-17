import SwiftUI

struct DetailCastStripView: View {
    let members: [TvCastMember]?
    let castNames: [String]?
    let client: LunaCoreClient?
    var horizontalGutter: CGFloat = LunaTheme.horizontalGutter
    let onSelectActor: (String) -> Void

    var body: some View {
        if let members, !members.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Medvirkende")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.horizontal, horizontalGutter)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(members.prefix(12)) { member in
                            CastMemberCardButton(member: member, client: client) {
                                onSelectActor(member.name)
                            }
                        }
                    }
                    .padding(.horizontal, horizontalGutter)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
            }
        } else if let castNames, !castNames.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Medvirkende")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LunaTheme.linen)
                    .padding(.horizontal, horizontalGutter)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(castNames.prefix(12), id: \.self) { actor in
                            LunaPillButton(actor, prominence: .subtleChip) {
                                onSelectActor(actor)
                            }
                        }
                    }
                    .padding(.horizontal, horizontalGutter)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
            }
        }
    }
}

private struct CastMemberCardButton: View {
    let member: TvCastMember
    let client: LunaCoreClient?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                CachedArtworkView(
                    url: client?.resolveArtworkURL(member.profileUrl),
                    client: client,
                    maxPixelSize: 220,
                    placeholderSymbol: "person.fill",
                    contentMode: .fill
                )
                .frame(width: 112, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous)
                        .strokeBorder(
                            isFocused ? LunaTheme.amber : LunaTheme.cardBorderColor(isFocused: false),
                            lineWidth: isFocused ? 2.2 : 1
                        )
                )
                .shadow(
                    color: isFocused ? LunaTheme.amber.opacity(0.32) : .clear,
                    radius: isFocused ? 14 : 0,
                    x: 0,
                    y: isFocused ? 5 : 0
                )

                Text(member.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LunaTheme.cardTitleColor(isFocused: isFocused))
                    .lineLimit(1)

                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.caption2)
                        .foregroundStyle(LunaTheme.cardSubtitleColor(isFocused: isFocused))
                        .lineLimit(1)
                }
            }
            .frame(width: 116, alignment: .leading)
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: LunaTheme.cardRadius, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
