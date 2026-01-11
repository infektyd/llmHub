import Foundation

/// Determines which conversations a context-menu action should apply to.
///
/// macOS convention in this app (Finder-style):
/// - If the context-clicked row is within the current selection, actions apply to the whole selection.
/// - Otherwise, actions apply only to the clicked row.
enum ConversationContextMenuTargetResolver {
    static func targetIDs(clickedID: UUID, selectedIDs: Set<UUID>) -> Set<UUID> {
        guard !selectedIDs.isEmpty else { return [clickedID] }

        // Finder-style behavior:
        // - If the context-clicked row is within the current selection, operate on the selection.
        // - Otherwise, operate only on the clicked row.
        if selectedIDs.contains(clickedID) {
            return selectedIDs
        }
        return [clickedID]
    }
}
