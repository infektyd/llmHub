//
//  NordicTextField.swift
//  llmHub
//
//  Clean input field with subtle border and focus state.
//

import SwiftUI

/// A minimalist text field with focus-aware border styling
struct NordicTextField: View {
    @Environment(\.colorScheme) private var colorScheme

    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(fieldBackground)
            .focused($isFocused)
            .onSubmit { onSubmit?() }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(NordicColors.surface(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    /// Border color changes to terracotta when focused
    private var borderColor: Color {
        if isFocused {
            return NordicColors.accentPrimary(colorScheme)
        }
        return NordicColors.border(colorScheme)
    }
}

// MARK: - Preview Wrapper

private struct TextFieldPreviewWrapper: View {
    @State private var text: String

    init(initialText: String = "") {
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NordicTextField(
            placeholder: "Enter text...", text: $text,
            onSubmit: {
                print("Submitted: \(text)")
            })
    }
}

// MARK: - Previews

#Preview("Empty") {
    TextFieldPreviewWrapper()
        .padding()
        .frame(width: 300)
        .previewEnvironment()
}

#Preview("With Text") {
    TextFieldPreviewWrapper(initialText: "Sample text")
        .padding()
        .frame(width: 300)
        .previewEnvironment()
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        TextFieldPreviewWrapper()
        TextFieldPreviewWrapper(initialText: "Filled field")
    }
    .padding()
    .frame(width: 300)
    .previewEnvironment()
}

#Preview("Multiple Fields") {
    VStack(spacing: 16) {
        TextFieldPreviewWrapper()
        TextFieldPreviewWrapper(initialText: "Name")
        TextFieldPreviewWrapper(initialText: "Email@example.com")
    }
    .padding()
    .frame(width: 350)
    .previewEnvironment()
}
