import SwiftUI
import UIKit

struct MarkedSearchTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var autocapitalization: UITextAutocapitalizationType = .words
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .search
    var isFocused: Binding<Bool>?
    var dismissToken: Int = 0
    var onInputChange: (String) -> Void = { _ in }
    var onChange: () -> Void
    var onBeginEditing: () -> Void = {}
    var onSubmit: () -> Void = {}

    init(
        placeholder: String,
        text: Binding<String>,
        autocapitalization: UITextAutocapitalizationType = .words,
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .search,
        isFocused: Binding<Bool>? = nil,
        dismissToken: Int = 0,
        onInputChange: @escaping (String) -> Void = { _ in },
        onChange: @escaping () -> Void,
        onBeginEditing: @escaping () -> Void = {},
        onSubmit: @escaping () -> Void = {}
    ) {
        self.placeholder = placeholder
        _text = text
        self.autocapitalization = autocapitalization
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.isFocused = isFocused
        self.dismissToken = dismissToken
        self.onInputChange = onInputChange
        self.onChange = onChange
        self.onBeginEditing = onBeginEditing
        self.onSubmit = onSubmit
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.placeholder = placeholder
        textField.borderStyle = .none
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.autocapitalizationType = autocapitalization
        textField.keyboardType = keyboardType
        textField.returnKeyType = returnKeyType
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text,
           uiView.markedTextRange == nil,
           !uiView.isFirstResponder {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.autocapitalizationType = autocapitalization
        uiView.keyboardType = keyboardType
        uiView.returnKeyType = returnKeyType
        context.coordinator.parent = self
        if !uiView.isFirstResponder {
            context.coordinator.syncExternalText(text)
        }

        if context.coordinator.lastDismissToken != dismissToken {
            context.coordinator.lastDismissToken = dismissToken
            uiView.text = text
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MarkedSearchTextField
        var lastDismissToken: Int
        private var lastNotifiedText: String
        private var lastNotifiedInputText: String

        init(parent: MarkedSearchTextField) {
            self.parent = parent
            lastDismissToken = parent.dismissToken
            lastNotifiedText = parent.text
            lastNotifiedInputText = parent.text
        }

        @objc func editingChanged(_ sender: UITextField) {
            notifyInputChanged(from: sender)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            notifyInputChanged(from: textField)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused?.wrappedValue = true
            parent.onBeginEditing()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused?.wrappedValue = false
            notifyCommittedText(textField.text ?? "")
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            notifyCommittedText(textField.text ?? "")
            parent.onSubmit()
            textField.resignFirstResponder()
            return true
        }

        func syncExternalText(_ text: String) {
            guard text != lastNotifiedText ||
                  text != lastNotifiedInputText else {
                return
            }

            lastNotifiedText = text
            lastNotifiedInputText = text
        }

        private func notifyInputChanged(from textField: UITextField) {
            let currentText = currentInputText(from: textField)
            if textField.markedTextRange == nil {
                parent.text = currentText
            }
            notifyTransientInput(currentText)
        }

        private func currentInputText(from textField: UITextField) -> String {
            let baseText = textField.text ?? ""
            guard let markedRange = textField.markedTextRange,
                  let markedText = textField.text(in: markedRange),
                  !markedText.isEmpty else {
                return baseText
            }

            if baseText.contains(markedText) {
                return baseText
            }

            let start = textField.offset(from: textField.beginningOfDocument, to: markedRange.start)
            let end = textField.offset(from: textField.beginningOfDocument, to: markedRange.end)
            guard start >= 0, end >= start else {
                return baseText.isEmpty ? markedText : baseText
            }

            let nsText = baseText as NSString
            guard end <= nsText.length else {
                return baseText.isEmpty ? markedText : baseText
            }

            return nsText.replacingCharacters(
                in: NSRange(location: start, length: end - start),
                with: markedText
            )
        }

        private func notifyTransientInput(_ text: String) {
            guard text != lastNotifiedInputText else { return }
            lastNotifiedInputText = text
            parent.onInputChange(text)
        }

        private func notifyCommittedText(_ text: String) {
            let inputChanged = text != lastNotifiedInputText
            let committedChanged = text != lastNotifiedText
            guard inputChanged || committedChanged else { return }
            lastNotifiedText = text
            lastNotifiedInputText = text
            parent.text = text
            parent.onInputChange(text)
            parent.onChange()
        }
    }
}
