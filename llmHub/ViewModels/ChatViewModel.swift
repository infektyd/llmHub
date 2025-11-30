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

enum ChatViewMode: String, CaseIterable, Identifiable {
    case date = "Date"
    case folder = "Folder"
    case provider = "Provider"
    
    var id: String { rawValue }
}

struct ChatSection: Identifiable {
    let id: String
    let title: String
    var sessions: [ChatSession]
    var isExpanded: Bool = true
    var folder: ChatFolder? = nil // For folder operations
}

@MainActor
final class ChatViewModel: ObservableObject {
    private let service: ChatService
    private let logger = Logger(subsystem: "com.llmhub", category: "ChatViewModel")

    @Published var sessions: [ChatSession] = []
    @Published var folders: [ChatFolder] = []
    @Published var tags: [ChatTag] = []
    @Published var selectedSession: ChatSession?
    @Published var isLoading = false
    @Published var viewMode: ChatViewMode = .date
    @Published var availableProviders: [any LLMProvider] = []
    
    // For filtering
    @Published var selectedTags: Set<UUID> = []

    init(service: ChatService) {
        self.service = service
        updateAvailableProviders()
    }
    
    var groupedSessions: [ChatSection] {
        let filteredSessions = sessions.filter { session in
            if selectedTags.isEmpty { return true }
            // Check if session has ANY of the selected tags
            return session.tags.contains { selectedTags.contains($0.id) }
        }
        
        let pinnedSessions = filteredSessions.filter { $0.isPinned }
        let unpinnedSessions = filteredSessions.filter { !$0.isPinned }
        
        var sections: [ChatSection] = []
        
        // Always show pinned section if there are pinned items
        if !pinnedSessions.isEmpty {
            sections.append(ChatSection(id: "pinned", title: "Pinned", sessions: pinnedSessions))
        }
        
        switch viewMode {
        case .date:
            let grouped = Dictionary(grouping: unpinnedSessions) { session -> String in
                if Calendar.current.isDateInToday(session.updatedAt) { return "Today" }
                if Calendar.current.isDateInYesterday(session.updatedAt) { return "Yesterday" }
                let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                if session.updatedAt > weekAgo { return "Previous 7 Days" }
                let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
                if session.updatedAt > monthAgo { return "Previous 30 Days" }
                return "Older"
            }
            
            let order = ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "Older"]
            for key in order {
                if let sessions = grouped[key], !sessions.isEmpty {
                    sections.append(ChatSection(id: key, title: key, sessions: sessions.sorted(by: { $0.updatedAt > $1.updatedAt })))
                }
            }
            
        case .folder:
            // Group by folder ID
            let grouped = Dictionary(grouping: unpinnedSessions) { $0.folderID }
            
            // Defined folders
            for folder in folders {
                if let sessions = grouped[folder.id], !sessions.isEmpty {
                    sections.append(ChatSection(id: folder.id.uuidString, title: folder.name, sessions: sessions, folder: folder))
                } else {
                     // Show empty folders too so we can drag into them? 
                     // Usually yes, but maybe specific UI for that. 
                     // For now let's show them.
                     sections.append(ChatSection(id: folder.id.uuidString, title: folder.name, sessions: [], folder: folder))
                }
            }
            
            // Unfiled
            if let unfiled = grouped[nil], !unfiled.isEmpty {
                sections.append(ChatSection(id: "unfiled", title: "Unfiled", sessions: unfiled))
            }
            
        case .provider:
            let grouped = Dictionary(grouping: unpinnedSessions) { $0.providerID }
            for (providerID, sessions) in grouped {
                sections.append(ChatSection(id: providerID, title: providerID.uppercased(), sessions: sessions.sorted(by: { $0.updatedAt > $1.updatedAt })))
            }
            // Sort sections by provider name
            let pinnedCount = !pinnedSessions.isEmpty ? 1 : 0
            if sections.count > pinnedCount {
                let slice = sections[pinnedCount...]
                let sorted = slice.sorted { $0.title < $1.title }
                sections.replaceSubrange(pinnedCount..<sections.count, with: sorted)
            }
        }
        
        return sections
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
            folders = try service.loadFolders()
            tags = try service.loadTags()
            
            // Keep selection if valid, otherwise default
            if selectedSession == nil {
                selectedSession = sessions.first
            } else if !sessions.contains(where: { $0.id == selectedSession?.id }) {
                 selectedSession = sessions.first
            }
        } catch {
            logger.error("Failed to load data: \(error)")
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
    
    // MARK: - Organization Actions
    
    func createFolder(name: String, icon: String, color: String) {
        do {
            _ = try service.createFolder(name: name, icon: icon, color: color)
            loadSessions() // Reload all
        } catch {
             logger.error("Failed to create folder: \(error)")
        }
    }
    
    func deleteFolder(id: UUID) {
        do {
            try service.deleteFolder(id: id)
            loadSessions()
        } catch {
            logger.error("Failed to delete folder: \(error)")
        }
    }
    
    func moveSession(_ session: ChatSession, to folder: ChatFolder?) {
        do {
            try service.moveSession(session.id, to: folder?.id)
            loadSessions()
        } catch {
            logger.error("Failed to move session: \(error)")
        }
    }
    
    func togglePin(_ session: ChatSession) {
        do {
            try service.togglePin(sessionID: session.id)
            loadSessions()
        } catch {
            logger.error("Failed to toggle pin: \(error)")
        }
    }
    
    func createTag(name: String, color: String) {
        do {
            _ = try service.createTag(name: name, color: color)
            loadSessions()
        } catch {
            logger.error("Failed to create tag: \(error)")
        }
    }
    
    func deleteTag(id: UUID) {
        do {
            try service.deleteTag(id: id)
            loadSessions()
        } catch {
             logger.error("Failed to delete tag: \(error)")
        }
    }
    
    func addTag(_ tag: ChatTag, to session: ChatSession) {
        do {
            try service.addTag(tagID: tag.id, to: session.id)
            loadSessions()
        } catch {
             logger.error("Failed to add tag: \(error)")
        }
    }
    
    func removeTag(_ tag: ChatTag, from session: ChatSession) {
        do {
            try service.removeTag(tagID: tag.id, from: session.id)
            loadSessions()
        } catch {
             logger.error("Failed to remove tag: \(error)")
        }
    }

    func send(userMessage: String, images: [Data] = []) async {
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
            let stream = try await service.streamCompletion(for: session, userMessage: userMessage, images: images)
            
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
