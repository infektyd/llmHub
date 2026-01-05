import Foundation

/// Ensures classification is debounced to at most one in-flight task per conversation.
actor ConversationClassificationDebouncer {
    static let shared = ConversationClassificationDebouncer()

    private var inFlightSessionIDs: Set<UUID> = []

    func begin(sessionID: UUID) -> Bool {
        guard !inFlightSessionIDs.contains(sessionID) else { return false }
        inFlightSessionIDs.insert(sessionID)
        return true
    }

    func end(sessionID: UUID) {
        inFlightSessionIDs.remove(sessionID)
    }
}
