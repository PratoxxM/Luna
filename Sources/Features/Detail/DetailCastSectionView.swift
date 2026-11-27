import SwiftUI

struct DetailCastSectionView: View {
    let castMembers: [TvCastMember]
    let client: LunaCoreClient?
    let detailGutter: CGFloat
    var onSelectCastMember: ((TvCastMember) -> Void)? = nil

    @FocusState private var focusedMemberID: String?
    @Namespace private var castFocusNamespace

    private static let cardWidth: CGFloat = 180
    private static let cardHeight: CGFloat = 270

    var body: some View {
        let members = Array(castMembers.prefix(12))
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: LunaTokens.Layout.headerGap) {
                LunaSectionHeader(
                    title: "Medvirkende",
                    metaText: LunaCopy.plural(members.count, "person", "personer")
                )
                .padding(.horizontal, detailGutter)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 24) {
                        ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                            CastMemberCardButton(
                                member: member,
                                client: client,
                                cardWidth: Self.cardWidth,
                                cardHeight: Self.cardHeight,
                                isFocused: focusedMemberID == member.id
                            ) {
                                onSelectCastMember?(member)
                            }
                            .focused($focusedMemberID, equals: member.id)
                            .prefersDefaultFocus(index == 0, in: castFocusNamespace)
                        }
                    }
                    .padding(.horizontal, detailGutter)
                    .padding(.vertical, 10)
                }
                .contentMargins(.zero, for: .scrollContent)
                .scrollClipDisabled()
                .focusScope(castFocusNamespace)
                .focusSection()
            }
        }
    }
}

private struct CastMemberCardButton: View {
    let member: TvCastMember
    let client: LunaCoreClient?
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        let profileURL = client?.resolveArtworkURL(member.profileUrl, target: .poster2x)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LunaTheme.surface

                    CachedArtworkView(
                        url: profileURL,
                        client: client,
                        maxPixelSize: 480,
                        placeholderSymbol: "person.fill",
                        contentMode: .fill
                    )
                    .equatable()
                    .frame(width: cardWidth, height: cardHeight)
                    .opacity(isFocused ? 1.0 : LunaTokens.Layout.restPosterBrightness)
                    .clipped()
                }
                .frame(width: cardWidth, height: cardHeight)
                .lunaCardFocusFrame(
                    cornerRadius: LunaTheme.posterRadius,
                    isFocused: isFocused
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(LunaTheme.Font.caption)
                        .foregroundStyle(isFocused ? LunaTheme.linen : LunaTheme.moonlight)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let role = member.character?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !role.isEmpty {
                        Text(role)
                            .font(LunaTheme.Font.badge)
                            .foregroundStyle(LunaTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: cardWidth, alignment: .leading)
            }
        }
        .lunaChromelessButton(RoundedRectangle(cornerRadius: LunaTheme.posterRadius, style: .continuous))
        .lunaCardLampGlow(isFocused: isFocused, cornerRadius: LunaTheme.posterRadius)
        .accessibilityLabel(
            member.character.map { "\(member.name), \($0)" } ?? member.name
        )
    }
}
