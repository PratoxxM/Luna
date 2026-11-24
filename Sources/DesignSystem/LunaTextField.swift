import SwiftUI
import UIKit

/// Lampelys dark-surface tvOS text input field that completely eliminates the bright white
/// system `UITextField` focus capsule on tvOS 18–26+, while opening the native full-screen
/// tvOS keyboard, Siri dictation, and iPhone Continuity Keyboard on `Select`.
public struct LunaTextField: View {
    let placeholder: String
    @Binding var text: String
    let leadingSystemImage: String?
    let keyboardType: UIKeyboardType
    let returnKeyType: UIReturnKeyType
    let autocapitalizationType: UITextAutocapitalizationType
    let onEditingEnded: (() -> Void)?
    let onSubmit: (() -> Void)?

    @FocusState private var isDirectFocused: Bool
    @State private var activationNonce: Int = 0
    @State private var isKeyboardPresented: Bool = false

    public init(
        _ placeholder: String,
        text: Binding<String>,
        leadingSystemImage: String? = nil,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .done,
        autocapitalizationType: UITextAutocapitalizationType = .none,
        onEditingEnded: (() -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.leadingSystemImage = leadingSystemImage
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.autocapitalizationType = autocapitalizationType
        self.onEditingEnded = onEditingEnded
        self.onSubmit = onSubmit
    }

    public nonisolated static func resolveSurfaceColor(isFocused: Bool) -> Color {
        isFocused ? LunaTheme.surfaceSelected : LunaTheme.surfaceRaised
    }

    public nonisolated static func resolveBorderColor(isFocused: Bool) -> Color {
        isFocused ? LunaTheme.focusGoldBorder.opacity(LunaFocusStyle.borderOpacity) : LunaTheme.warmBorder
    }

    public var body: some View {
        Button {
            activationNonce &+= 1
        } label: {
            LunaTextFieldLabel(
                placeholder: placeholder,
                text: text,
                leadingSystemImage: leadingSystemImage,
                externalFocus: isDirectFocused || isKeyboardPresented
            ) {
                HiddenTVKeyboardHost(
                    placeholder: placeholder,
                    text: $text,
                    activationNonce: activationNonce,
                    keyboardType: keyboardType,
                    returnKeyType: returnKeyType,
                    autocapitalizationType: autocapitalizationType,
                    onBeginEditing: {
                        isKeyboardPresented = true
                    },
                    onEndEditing: {
                        isKeyboardPresented = false
                        isDirectFocused = true
                        onEditingEnded?()
                    },
                    onSubmit: onSubmit
                )
                .frame(width: 2, height: 2)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .lunaChromelessButton(RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous))
        .focused($isDirectFocused)
        .accessibilityLabel(placeholder)
        .accessibilityValue(text)
    }
}

private struct LunaTextFieldLabel<HiddenField: View>: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lunaRoomAtmosphere) private var roomAtmosphere

    let placeholder: String
    let text: String
    let leadingSystemImage: String?
    let externalFocus: Bool
    @ViewBuilder let hiddenField: () -> HiddenField

    private var effectiveFocused: Bool {
        isFocused || externalFocus
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LunaTokens.Radius.card, style: .continuous)
        let scale = (reduceMotion || !effectiveFocused) ? 1.0 : LunaTokens.Layout.focusScaleRow

        HStack(spacing: 14) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(LunaTheme.Font.pillIcon)
                    .foregroundStyle(effectiveFocused ? LunaTheme.amber : LunaTheme.muted)
            }

            Text(text.isEmpty ? placeholder : text)
                .font(LunaTheme.Font.body)
                .foregroundStyle(text.isEmpty ? LunaTheme.muted : LunaTheme.linen)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, minHeight: LunaTokens.Layout.controlH, alignment: .leading)
        .background {
            ZStack {
                hiddenField()
                shape.fill(LunaTextField.resolveSurfaceColor(isFocused: effectiveFocused))
            }
        }
        .overlay {
            shape.strokeBorder(
                LunaTextField.resolveBorderColor(isFocused: effectiveFocused),
                lineWidth: effectiveFocused ? LunaFocusStyle.borderWidth : LunaTokens.Layout.hairlineWidth
            )
            .transaction { $0.animation = nil }
        }
        .shadow(
            color: effectiveFocused ? roomAtmosphere.lampColor.opacity(roomAtmosphere.lampStrength * 0.72) : .clear,
            radius: effectiveFocused ? LunaFocusStyle.glowBlur : 0,
            x: 0,
            y: effectiveFocused ? LunaFocusStyle.glowOffsetY : 0
        )
        .scaleEffect(scale)
        .animation(LunaFocusStyle.spring(reduceMotion: reduceMotion), value: effectiveFocused)
    }
}

@MainActor
internal final class NonFocusableTVTextField: UITextField {
    override var canBecomeFocused: Bool {
        false
    }
}

@MainActor
private struct HiddenTVKeyboardHost: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let activationNonce: Int
    let keyboardType: UIKeyboardType
    let returnKeyType: UIReturnKeyType
    let autocapitalizationType: UITextAutocapitalizationType
    let onBeginEditing: () -> Void
    let onEndEditing: () -> Void
    let onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> NonFocusableTVTextField {
        let tf = NonFocusableTVTextField(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartQuotesType = .no
        tf.smartDashesType = .no
        tf.placeholder = placeholder
        tf.text = text
        tf.keyboardType = keyboardType
        tf.returnKeyType = returnKeyType
        tf.autocapitalizationType = autocapitalizationType
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ uiView: NonFocusableTVTextField, context: Context) {
        context.coordinator.parent = self
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }
        if uiView.keyboardType != keyboardType {
            uiView.keyboardType = keyboardType
        }
        if uiView.returnKeyType != returnKeyType {
            uiView.returnKeyType = returnKeyType
        }
        if uiView.autocapitalizationType != autocapitalizationType {
            uiView.autocapitalizationType = autocapitalizationType
        }
        if !uiView.isFirstResponder && uiView.text != text {
            uiView.text = text
        }
        if activationNonce != context.coordinator.appliedActivationNonce {
            context.coordinator.appliedActivationNonce = activationNonce
            DispatchQueue.main.async { [weak uiView] in
                guard let uiView, uiView.window != nil else { return }
                if uiView.text != context.coordinator.parent.text {
                    uiView.text = context.coordinator.parent.text
                }
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: HiddenTVKeyboardHost
        var appliedActivationNonce: Int = 0

        init(parent: HiddenTVKeyboardHost) {
            self.parent = parent
        }

        @objc func editingChanged(_ sender: UITextField) {
            let next = sender.text ?? ""
            if parent.text != next {
                parent.text = next
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onBeginEditing()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let next = textField.text ?? ""
            if parent.text != next {
                parent.text = next
            }
            parent.onEndEditing()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            let next = textField.text ?? ""
            if parent.text != next {
                parent.text = next
            }
            textField.resignFirstResponder()
            parent.onSubmit?()
            return true
        }
    }
}
