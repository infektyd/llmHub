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
            // Text field - plain, no individual background
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
                .lineLimit(1...6)
                .frame(maxWidth: .infinity, alignment: .leading)  // FIX: Expand to full width
                .contentShape(Rectangle())  // Better hit testing
                .onTapGesture {  // Explicit focus on tap
                    isFocused = true
                }
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                        // Don't clear focus - let user keep typing
                    }
                }

            // Send button
            Button(action: {
                onSend()
                isFocused = true  // Keep focus after sending
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? NordicColors.textSecondary(colorScheme)
                            : NordicColors.accentSecondary(colorScheme)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 08)
                .fill(NordicColors.surface(colorScheme))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12),
                    radius: 06,
                    y: 4
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear {
            // Auto-focus on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
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
        .previewEnvironment()
}

#Preview("With Text") {
    InputBarPreviewWrapper(initialText: "Hello, this is a sample message")
        .frame(width: 500)
        .previewEnvironment()
}

#Preview("Long Text") {
    InputBarPreviewWrapper(
        initialText:
            "This is a much longer message that will wrap to multiple lines to demonstrate how the input bar handles multi-line text input."
    )
    .frame(width: 500)
    .previewEnvironment()
}

#Preview("Dark Mode") {
    VStack {
        Spacer()
        InputBarPreviewWrapper(initialText: "Dark mode message")
    }
    .frame(width: 500, height: 400)
    .previewEnvironment()
}
