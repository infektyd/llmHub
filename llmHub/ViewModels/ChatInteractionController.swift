//
//  ChatInteractionController.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/12/25.
//

import Combine
import SwiftUI

/// Manages chat-scoped interactions such as text selection, reference creation, and auto-copy.
@MainActor
class ChatInteractionController: ObservableObject {
    deinit {
        print("🗑️ ChatInteractionController deallocated")
    }

    // MARK: - State

    /// The currently selected text in a valid chat message.
    @Published var activeSelection: String?

    /// The ID of the message where the selection occurred.
    @Published var selectionSourceID: UUID?

    /// The role of the message where the selection occurred.
    @Published var selectionSourceRole: MessageRole?

    // MARK: - Dependencies

    // We hold a weak reference or closure to inject references into the ViewModel
    // to avoid strong reference cycles if this controller is owned by the View.
    var onAddReference: ((ChatReference) -> Void)?

    // MARK: - Configuration

    @AppStorage("chatAutoCopyEnabled") private var autoCopyEnabled: Bool = false
    private let minAutoCopyLength = 8
    private var lastAutoCopyTime: Date = .distantPast

    // MARK: - Actions

    /// Updates the active selection state.
    /// - Parameters:
    ///   - text: The selected text.
    ///   - messageID: The source message ID.
    ///   - role: The source message role.
    func handleSelectionChange(text: String?, messageID: UUID?, role: MessageRole?) {
        self.activeSelection = text
        self.selectionSourceID = messageID
        self.selectionSourceRole = role

        // Auto-Copy Logic (macOS only)
        #if os(macOS)
            if let text = text, !text.isEmpty,
                let role = role,
                autoCopyEnabled {
                processAutoCopy(text: text, role: role)
            }
        #endif
    }

    /// Creates a ChatReference from the current active selection and triggers the callback.
    func addSelectionAsReference() {
        guard let text = activeSelection, !text.isEmpty,
            let messageID = selectionSourceID,
            let role = selectionSourceRole
        else {
            return
        }

        let reference = ChatReference(
            text: text,
            sourceMessageID: messageID,
            role: role
        )

        onAddReference?(reference)

        // Clear selection state after adding?
        // Typically we keep the selection visually, but we might want to feedback.
        // For now, keep it active.
    }

    /// Creates a ChatReference from a whole message (no selection required) and triggers the callback.
    func addMessageAsReference(text: String, messageID: UUID, role: MessageRole) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Only allow Assistant or Tool messages.
        guard role == .assistant || role == .tool else { return }

        let reference = ChatReference(
            text: trimmed,
            sourceMessageID: messageID,
            role: role
        )
        onAddReference?(reference)
    }

    // MARK: - Internal Logic

    #if os(macOS)
        private func processAutoCopy(text: String, role: MessageRole) {
            // safeguards
            guard text.count >= minAutoCopyLength else { return }

            // Only allow Assistant or Tool messages (User input should never auto-copy)
            guard role == .assistant || role == .tool else { return }

            // Debounce (simple time check)
            let now = Date()
            guard now.timeIntervalSince(lastAutoCopyTime) > 0.5 else { return }

            lastAutoCopyTime = now

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

            print("📋 Auto-copied selection from \(role.rawValue) (\(text.prefix(20))...)")
        }
    #endif
}
