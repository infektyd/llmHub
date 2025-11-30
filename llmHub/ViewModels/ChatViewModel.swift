//
//  ChatViewModel.swift
//  llmHub
//
//  Created by Hans Axelsson on 11/27/25.
//

import SwiftUI
import SwiftData
import Combine
import OSLog

final class ChatViewModel: ObservableObject {
    private let service: ChatService
    private let logger = Logger(subsystem: "com.llmhub", category: "ChatViewModel")

    @Published var sessions: [ChatSession] = []
    @Published var selectedSession: ChatSession?
    @Published var isLoading = false

    @Published var availableProviders: [any LLMProvider] = []
    
    init(service: ChatService) {
        self.service = service
        updateAvailableProviders()
    }
    
    func updateAvailableProviders() {
        availableProviders = service.providerRegistry.availableProviders.filter { $0.isConfigured }
    }
    
    func fetchModels(for providerID: String) async -> [LLMModel] {

        guard let provider = try? service.providerRegistry.provider(for: providerID) else { 

            logger.error("Provider not found: \(providerID)")

            return [] 

        }

        do {

            return try await provider.fetchModels()

        } catch {

            logger.error("Failed to fetch models for \(providerID): \(error)")

            return []

        }

    }

    func loadSessions() {
        do {
            sessions = try service.loadSessions()
            selectedSession = sessions.first
        } catch {
            logger.error("Failed to load sessions: \(error)")
        }
    }

    func startSession(providerID: String, model: String) {
        do {
            let session = try service.createSession(providerID: providerID, model: model)
            sessions.insert(session, at: 0)
            selectedSession = session
        } catch {
            logger.error("Failed to create session: \(error)")
        }
    }

    @MainActor
    func send(userMessage: String) async {
        guard let session = selectedSession else { return }
        isLoading = true
        defer { isLoading = false }

        // Create temporary assistant message
        let assistantID = UUID()
        var assistantMessage = ChatMessage(
            id: assistantID,
            role: .assistant,
            content: "",
            parts: [],
            createdAt: Date(),
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil
        )
        
        // Append empty assistant message immediately
        if var currentSession = selectedSession {
            currentSession.messages.append(assistantMessage)
            selectedSession = currentSession
        }

        do {
            let stream = try await service.streamCompletion(for: session, userMessage: userMessage)
            
            // Need to reload to see the user message we just saved in service
            if let updated = try? service.loadSession(id: session.id) {
                // Re-attach our temporary assistant message
                var msgs = updated.messages
                msgs.append(assistantMessage)
                var sessionWithUser = updated
                sessionWithUser.messages = msgs
                selectedSession = sessionWithUser
            }
            
            for try await event in stream {
                switch event {
                case .token(let text):
                    assistantMessage.content += text
                    updateAssistantMessage(assistantMessage)
                    
                case .thinking(let thought):
                    let current = assistantMessage.thoughtProcess ?? ""
                    assistantMessage.thoughtProcess = current + thought
                    updateAssistantMessage(assistantMessage)
                    
                case .completion(let finalMessage):
                    // Save final message to DB via service
                    // Note: service.streamCompletion doesn't save assistant response anymore, we must do it
                    try service.appendMessage(finalMessage, to: session.id)
                    loadSessions() // Reload from source of truth
                    
                case .error(let error):
                    assistantMessage.content += "\n[Error: \(error.localizedDescription)]"
                    updateAssistantMessage(assistantMessage)
                    
                default:
                    break
                }
            }
        } catch {
            logger.error("Failed to send message: \(error)")
            assistantMessage.content += "\n[Failed: \(error.localizedDescription)]"
            updateAssistantMessage(assistantMessage)
        }
    }

    private func updateAssistantMessage(_ message: ChatMessage) {
        guard var session = selectedSession else { return }
        if let index = session.messages.firstIndex(where: { $0.id == message.id }) {
            session.messages[index] = message
        } else {
            session.messages.append(message)
        }
        selectedSession = session
    }
}
