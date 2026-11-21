import SwiftUI

/// Canonical sentence-case section header with optional muted trailing metadata or action.
public struct LunaSectionHeader<Trailing: View>: View {
    let title: String
    let metaText: String?
    @ViewBuilder let trailing: () -> Trailing

    public init(
        title: String,
        metaText: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.metaText = metaText
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(LunaTheme.Font.sectionTitle)
                .foregroundStyle(LunaTheme.linen)
                .lineLimit(1)

            Spacer(minLength: 16)

            if let metaText, !metaText.isEmpty {
                Text(metaText)
                    .font(LunaTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
            }

            trailing()
        }
    }
}

public extension LunaSectionHeader where Trailing == EmptyView {
    init(title: String, metaText: String? = nil) {
        self.init(title: title, metaText: metaText) {
            EmptyView()
        }
    }
}

/// Single-frame container (`r18` `Surface.lv1` + `0.5 pt` top light edge) for grouped rows,
/// or a frameless vertical stack (`showsSurface: false`) when placed directly inside a sheet/popover.
public struct LunaListGroup<Content: View>: View {
    let showsSurface: Bool
    @ViewBuilder let content: () -> Content

    public init(showsSurface: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.showsSurface = showsSurface
        self.content = content
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
        let stack = VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if showsSurface {
            stack
                .background(shape.fill(LunaTheme.surface))
                .clipShape(shape)
                .lunaTopLightEdge(
                    cornerRadius: LunaTokens.Radius.card,
                    topColor: LunaTokens.Edge.top1,
                    lineWidth: LunaTokens.Layout.hairlineWidth
                )
        } else {
            stack
        }
    }
}

/// Inset `0.5 pt` divider matching `@2x` 1-pixel physical hairlines between rows inside `LunaListGroup`.
public struct LunaListDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(LunaTokens.Edge.divider)
            .frame(height: LunaTokens.Layout.hairlineWidth)
            .padding(.horizontal, LunaTokens.Layout.listRowPadX)
    }
}

/// Read-only key/value row inside a `LunaListGroup` or `LunaSheetContainer`.
public struct LunaInfoRow: View {
    let title: String
    let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(LunaTheme.Font.subtitle)
                .foregroundStyle(LunaTheme.muted)
            Spacer(minLength: 16)
            Text(value)
                .font(LunaTheme.Font.subtitle.monospacedDigit())
                .foregroundStyle(LunaTheme.moonlight)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, LunaTokens.Layout.listRowPadX)
        .padding(.vertical, 14)
        .frame(minHeight: 60)
    }
}

/// Non-interactive container row pairing a title (and optional 1-line data subtitle) with inline controls.
public struct LunaControlRow<Controls: View>: View {
    let title: String
    let subtitle: String?
    let axis: Axis
    @ViewBuilder let controls: () -> Controls

    public init(
        title: String,
        subtitle: String? = nil,
        axis: Axis = .horizontal,
        @ViewBuilder controls: @escaping () -> Controls
    ) {
        self.title = title
        self.subtitle = subtitle
        self.axis = axis
        self.controls = controls
    }

    private var labelBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LunaTheme.Font.cardTitle)
                .foregroundStyle(LunaTheme.linen)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(LunaTheme.Font.subtitle)
                    .foregroundStyle(LunaTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    public var body: some View {
        Group {
            if axis == .horizontal {
                HStack(alignment: .center, spacing: 20) {
                    labelBlock
                        .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

                    controls()
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    labelBlock
                        .frame(maxWidth: .infinity, alignment: .leading)

                    controls()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, LunaTokens.Layout.listRowPadX)
        .padding(.vertical, LunaTokens.Layout.listRowPadY)
        .frame(minHeight: LunaTokens.Layout.listRowMinH)
    }
}

/// Canonical interactive row (`minH 72`, `1.0x` scale, `surfaceSelected` + `3 pt` leading amber bar on focus).
public struct LunaListRow: View {
    let title: String
    let subtitle: String?
    let leadingSystemImage: String?
    let trailingText: String?
    let trailingTextProminent: Bool
    let isSelected: Bool
    let showsChevron: Bool
    let isDestructive: Bool
    let dimUnfocusedTitle: Bool
    let cornerRadius: CGFloat
    let externalIsFocused: Bool?
    let action: () -> Void

    @FocusState private var isDirectFocused: Bool

    public init(
        title: String,
        subtitle: String? = nil,
        leadingSystemImage: String? = nil,
        trailingText: String? = nil,
        trailingTextProminent: Bool = false,
        isSelected: Bool = false,
        showsChevron: Bool = false,
        isDestructive: Bool = false,
        dimUnfocusedTitle: Bool = false,
        cornerRadius: CGFloat = LunaTokens.Radius.card,
        externalIsFocused: Bool? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leadingSystemImage = leadingSystemImage
        self.trailingText = trailingText
        self.trailingTextProminent = trailingTextProminent
        self.isSelected = isSelected
        self.showsChevron = showsChevron
        self.isDestructive = isDestructive
        self.dimUnfocusedTitle = dimUnfocusedTitle
        self.cornerRadius = cornerRadius
        self.externalIsFocused = externalIsFocused
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            LunaListRowLabel(
                title: title,
                subtitle: subtitle,
                leadingSystemImage: leadingSystemImage,
                trailingText: trailingText,
                trailingTextProminent: trailingTextProminent,
                isSelected: isSelected,
                showsChevron: showsChevron,
                isDestructive: isDestructive,
                dimUnfocusedTitle: dimUnfocusedTitle,
                cornerRadius: cornerRadius,
                externalIsFocused: externalIsFocused,
                directFocused: isDirectFocused
            )
        }
        .lunaChromelessButton(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .focused($isDirectFocused)
    }
}

private struct LunaListRowLabel: View {
    @Environment(\.isFocused) private var envFocused

    let title: String
    let subtitle: String?
    let leadingSystemImage: String?
    let trailingText: String?
    let trailingTextProminent: Bool
    let isSelected: Bool
    let showsChevron: Bool
    let isDestructive: Bool
    let dimUnfocusedTitle: Bool
    let cornerRadius: CGFloat
    let externalIsFocused: Bool?
    let directFocused: Bool

    private var effectiveFocused: Bool {
        externalIsFocused ?? (envFocused || directFocused)
    }

    var body: some View {
        HStack(spacing: 16) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(LunaTheme.Font.listRowIcon)
                    .foregroundStyle(
                        isDestructive
                            ? LunaTheme.coral
                            : (effectiveFocused ? LunaTheme.linen : LunaTheme.moonlight)
                    )
                    .frame(width: 28, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LunaTheme.Font.cardTitle)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LunaTheme.Font.subtitle)
                        .foregroundStyle(effectiveFocused ? LunaTheme.moonlight : LunaTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingText, !trailingText.isEmpty {
                Text(trailingText)
                    .font(
                        trailingTextProminent
                            ? LunaTheme.Font.caption.bold()
                            : LunaTheme.Font.subtitle.monospacedDigit()
                    )
                    .foregroundStyle(trailingColor)
                    .lineLimit(1)
                    .fixedSize()
            } else if isSelected {
                Image(systemName: "checkmark")
                    .font(LunaTheme.Font.listRowIcon)
                    .foregroundStyle(LunaTheme.amber)
                    .fixedSize()
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(LunaTheme.Font.microChevron)
                    .foregroundStyle(
                        effectiveFocused
                            ? (isDestructive ? LunaTheme.coral : LunaTheme.linen)
                            : LunaTheme.muted
                    )
                    .fixedSize()
            }
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, LunaTokens.Layout.listRowPadX)
        .padding(.vertical, LunaTokens.Layout.listRowPadY)
        .frame(minHeight: LunaTokens.Layout.listRowMinH)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    effectiveFocused
                        ? (isDestructive ? LunaTokens.Status.dangerBg : LunaTheme.surfaceSelected)
                        : Color.clear
                )
                .transaction { $0.animation = nil }
        )
        .lunaFocusSurface(
            .listRow,
            isFocused: effectiveFocused,
            cornerRadius: cornerRadius,
            accentColor: isDestructive ? LunaTheme.coral : LunaTheme.amber
        )
    }

    private var titleColor: Color {
        if isDestructive { return LunaTheme.coral }
        if dimUnfocusedTitle && !effectiveFocused && !isSelected {
            return LunaTheme.moonlight
        }
        return LunaTheme.linen
    }

    private var trailingColor: Color {
        if trailingTextProminent {
            return isDestructive ? LunaTheme.coral : LunaTheme.linen
        }
        return effectiveFocused ? LunaTheme.moonlight : LunaTheme.muted
    }
}
