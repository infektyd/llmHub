//
//  NordicInputBar.swift
//  llmHub
//
//  Input bar component for Nordic theme.
//  ZERO beta APIs - fully compatible with View Hierarchy Debugger.
//

import SwiftUI

/// Input bar for Nordic theme
struct NordicInputBar: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var text: String
    var onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Type a message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .lineLimit(1...6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(NordicColors.surface(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isFocused
                                ? NordicColors.accentPrimary(colorScheme)
                                : NordicColors.border(colorScheme),
                            lineWidth: isFocused ? 2 : 1
                        )
                )
                .focused($isFocused)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            // Send button
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? NordicColors.textMuted(colorScheme)
                            : NordicColors.accentSecondary(colorScheme)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NordicColors.canvas(colorScheme))
    }
}

// MARK: - Preview Wrapper

private struct InputBarPreviewWrapper: View {
    @State private var text: String

    init(initialText: String = "") {
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NordicInputBar(
            text: $text,
            onSend: {
                print("Send tapped: \(text)")
            })
    }
}

// MARK: - Previews

#Preview("Empty") {
    InputBarPreviewWrapper()
        .frame(width: 500)
}

#Preview("With Text") {
    InputBarPreviewWrapper(initialText: "Hello, this is a sample message")
        .frame(width: 500)
}

#Preview("Long Text") {
    InputBarPreviewWrapper(
        initialText:
            "This is a much longer message that will wrap to multiple lines to demonstrate how the input bar handles multi-line text input."
    )
    .frame(width: 500)
}

#Preview("Dark Mode") {
    VStack {
        Spacer()
        InputBarPreviewWrapper(initialText: "Dark mode message")
    }
    .frame(width: 500, height: 400)
    .background(NordicColors.Dark.canvas)
    .preferredColorScheme(.dark)
}
