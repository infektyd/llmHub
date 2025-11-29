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

    init(service: ChatService) {
        self.service = service
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

    func send(userMessage: String) async {
        guard let session = selectedSession else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let stream = try await service.streamCompletion(for: session, userMessage: userMessage)
            for try await event in stream {
                switch event {
                case .token:
                    break
                case .completion:
                    break
                case .usage:
                    break
                case .reference:
                    break
                case .error:
                    break
                case .toolUse:
                    break
                }
            }
            // Reload sessions or update
            loadSessions()
        } catch {
            logger.error("Failed to send message: \(error)")
        }
    }
}
