//
//  ChatDetailView.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftUI

struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.selectedSession?.messages ?? []) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .background(.thinMaterial)
                .onChange(of: viewModel.selectedSession?.messages.count ?? 0) { _, _ in
                    if let lastID = viewModel.selectedSession?.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .onSubmit {
                        Task { await send() }
                    }

                Button("Send") {
                    Task { await send() }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await viewModel.send(userMessage: text)
        inputText = ""
    }
}

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Assistant")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.content)
                .padding()
                .background(message.role == .user ? .blue.opacity(0.2) : .gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
