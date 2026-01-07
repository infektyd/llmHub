//
//  ConversationDistillationScheduler.swift
//  llmHub
//
//  Created by Agent on 2026-01-07.
//

import Foundation
import SwiftData
import os

@MainActor
final class ConversationDistillationScheduler: ConversationDistillationScheduling {
    static let shared = ConversationDistillationScheduler()

    private static var loggedUserDeleteSkips: Set<UUID> = []

    private let logger = Logger(subsystem: "com.llmhub", category: "DistillationScheduler")
    private let distillationService: ConversationDistillationService
    private let debounceNanoseconds: UInt64

    private var pendingDebounceTasks: [UUID: Task<Void, Never>] = [:]
    private var inFlightTasks: [UUID: Task<Void, Never>] = [:]

    init(
        distillationService: ConversationDistillationService = ConversationDistillationService(),
        debounceSeconds: TimeInterval = 2.0
    ) {
        self.distillationService = distillationService
        self.debounceNanoseconds = UInt64(max(0, debounceSeconds) * 1_000_000_000)
    }

    func scheduleDistillation(
        sessionID: UUID,
        providerID: String,
        messages: [ChatMessage],
        modelContext: ModelContext,
        reason: SessionEndReason
    ) {
        // Hard guard: user deletion must never trigger distillation/network/memory artifacts.
        if reason == .userDeleted {
            cancelDistillation(sessionID: sessionID)
            if !Self.loggedUserDeleteSkips.contains(sessionID) {
                Self.loggedUserDeleteSkips.insert(sessionID)
                logger.info("Skipping distillation: session deleted by user (id=\(sessionID))")
            }
            return
        }

        // Per product decision: distillation is allowed only for explicit archive.
        guard reason == .userArchived else {
            logger.debug("Skipping distillation: unsupported end reason (id=\(sessionID))")
            return
        }

        // Debounce: cancel any pending debounce for this session and reschedule.
        pendingDebounceTasks[sessionID]?.cancel()

        pendingDebounceTasks[sessionID] = Task { @MainActor in
            defer { pendingDebounceTasks[sessionID] = nil }

            if debounceNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                } catch {
                    // Cancelled during debounce.
                    return
                }
            }

            // Dedupe: if already in-flight, do not start another.
            if let existing = inFlightTasks[sessionID], !existing.isCancelled {
                logger.debug("Skipping distillation: already in-flight (id=\(sessionID))")
                return
            }

            let work = Task { @MainActor in
                defer { inFlightTasks[sessionID] = nil }
                if Task.isCancelled { return }

                await distillationService.distill(
                    sessionID: sessionID,
                    providerID: providerID,
                    messages: messages,
                    modelContext: modelContext
                )
            }

            inFlightTasks[sessionID] = work
        }
    }

    func cancelDistillation(sessionID: UUID) {
        pendingDebounceTasks[sessionID]?.cancel()
        pendingDebounceTasks[sessionID] = nil

        inFlightTasks[sessionID]?.cancel()
        inFlightTasks[sessionID] = nil
    }

    func cancelDistillation(sessionIDs: [UUID]) {
        for id in sessionIDs {
            cancelDistillation(sessionID: id)
        }
    }
}

