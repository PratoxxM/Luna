import SwiftUI

struct DetailCastStripView: View {
    let members: [TvCastMember]?
    let castNames: [String]?
    let client: MediaOSClient?
    let onSelectActor: (String) -> Void

    var body: some View {
        if let members, !members.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Medvirkende")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LunaTheme.moonlight)
                    .padding(.horizontal, LunaTheme.horizontalGutter)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(members.prefix(12)) { member in
                            CastMemberCardButton(member: member, client: client) {
                                onSelectActor(member.name)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
            }
        } else if let castNames, !castNames.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Medvirkende")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(LunaTheme.moonlight)
                    .padding(.horizontal, LunaTheme.horizontalGutter)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(castNames.prefix(12), id: \.self) { actor in
                            LunaPillButton(actor, prominence: .subtleChip) {
                                onSelectActor(actor)
                            }
                        }
                    }
                    .padding(.horizontal, LunaTheme.horizontalGutter)
                    .padding(.vertical, 10)
                }
                .scrollClipDisabled()
            }
        }
    }
}

private struct CastMemberCardButton: View {
    let member: TvCastMember
    let client: MediaOSClient?
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isFocused ? LunaTheme.amber : Color.white.opacity(0.10),
                            lineWidth: isFocused ? 2.5 : 1
                        )
                )
                .shadow(
                    color: isFocused ? LunaTheme.amber.opacity(0.35) : .clear,
                    radius: 14,
                    x: 0,
                    y: 6
                )

                Text(member.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFocused ? .white : LunaTheme.moonlight)
                    .lineLimit(1)

                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.caption2)
                        .foregroundStyle(isFocused ? LunaTheme.amber : LunaTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(width: 116, alignment: .leading)
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isFocused)
        }
        .buttonStyle(LunaChromelessButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .focusEffectDisabled(true)
        .focused($isFocused)
    }
}
