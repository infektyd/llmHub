import Foundation

/// Determines which conversations a context-menu action should apply to.
///
/// macOS convention in this app:
/// - If there is a multi-selection, context menu actions apply to the whole selection.
/// - Otherwise, they apply to the clicked row.
enum ConversationContextMenuTargetResolver {
    static func targetIDs(clickedID: UUID, selectedIDs: Set<UUID>) -> Set<UUID> {
        if selectedIDs.count > 1 {
            return selectedIDs
        }
        return [clickedID]
    }
}
