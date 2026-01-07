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
protocol ConversationDistillationServicing: AnyObject {
    func distill(
        sessionID: UUID,
        providerID: String,
        messages: [ChatMessage],
        modelContext: ModelContext
    ) async
}

extension ConversationDistillationService: ConversationDistillationServicing {}

@MainActor
final class ConversationDistillationScheduler: ConversationDistillationScheduling {
    static let shared = ConversationDistillationScheduler()

    private static var loggedUserDeleteSkips: Set<UUID> = []

    private let logger = Logger(subsystem: "com.llmhub", category: "DistillationScheduler")
    private let distillationService: ConversationDistillationServicing
    private let debounceNanoseconds: UInt64
    private let postFlightDebounceNanoseconds: UInt64

    private var pendingDebounceTasks: [UUID: Task<Void, Never>] = [:]
    private var inFlightTasks: [UUID: Task<Void, Never>] = [:]

    private struct Snapshot {
        let providerID: String
        let messages: [ChatMessage]
        let modelContext: ModelContext
        let reason: SessionEndReason
    }

    private var latestSnapshotBySessionID: [UUID: Snapshot] = [:]
    private var needsRerunAfterInFlight: Set<UUID> = []

    init(
        distillationService: ConversationDistillationServicing = ConversationDistillationService(),
        debounceSeconds: TimeInterval = 2.0,
        postFlightDebounceSeconds: TimeInterval = 0.2
    ) {
        self.distillationService = distillationService
        self.debounceNanoseconds = UInt64(max(0, debounceSeconds) * 1_000_000_000)
        self.postFlightDebounceNanoseconds = UInt64(max(0, postFlightDebounceSeconds) * 1_000_000_000)
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

        latestSnapshotBySessionID[sessionID] = Snapshot(
            providerID: providerID,
            messages: messages,
            modelContext: modelContext,
            reason: reason
        )

        scheduleDebouncedStart(sessionID: sessionID, delayNanoseconds: debounceNanoseconds)
    }

    private func scheduleDebouncedStart(sessionID: UUID, delayNanoseconds: UInt64) {
        // Debounce: cancel any pending debounce for this session and reschedule.
        pendingDebounceTasks[sessionID]?.cancel()

        pendingDebounceTasks[sessionID] = Task { @MainActor in
            defer { pendingDebounceTasks[sessionID] = nil }

            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    // Cancelled during debounce.
                    return
                }
            }

            await startIfPossible(sessionID: sessionID)
        }
    }

    private func startIfPossible(sessionID: UUID) async {
        guard let snapshot = latestSnapshotBySessionID[sessionID] else { return }

        // Dedupe: if already in-flight, coalesce into a single follow-up run.
        if let existing = inFlightTasks[sessionID], !existing.isCancelled {
            needsRerunAfterInFlight.insert(sessionID)
            logger.debug("Coalescing distillation: already in-flight (id=\(sessionID))")
            return
        }

        let work = Task { @MainActor in
            defer {
                inFlightTasks[sessionID] = nil
                if needsRerunAfterInFlight.contains(sessionID) {
                    needsRerunAfterInFlight.remove(sessionID)
                    // Run once more using the newest snapshot captured while in-flight.
                    scheduleDebouncedStart(sessionID: sessionID, delayNanoseconds: postFlightDebounceNanoseconds)
                }
            }
            if Task.isCancelled { return }

            await distillationService.distill(
                sessionID: sessionID,
                providerID: snapshot.providerID,
                messages: snapshot.messages,
                modelContext: snapshot.modelContext
            )
        }

        inFlightTasks[sessionID] = work
    }

    func cancelDistillation(sessionID: UUID) {
        pendingDebounceTasks[sessionID]?.cancel()
        pendingDebounceTasks[sessionID] = nil

        inFlightTasks[sessionID]?.cancel()
        inFlightTasks[sessionID] = nil

        latestSnapshotBySessionID[sessionID] = nil
        needsRerunAfterInFlight.remove(sessionID)
    }

    func cancelDistillation(sessionIDs: [UUID]) {
        for id in sessionIDs {
            cancelDistillation(sessionID: id)
        }
    }
}

