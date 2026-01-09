import XCTest

@testable import llmHub

@MainActor
final class ConversationContextMenuTargetResolverTests: XCTestCase {
    func testClickedInsideSelectionTargetsSelection() {
        let a = UUID()
        let b = UUID()
        let selected: Set<UUID> = [a, b]

        let targets = ConversationContextMenuTargetResolver.targetIDs(clickedID: a, selectedIDs: selected)
        XCTAssertEqual(targets, selected)
    }

    func testClickedOutsideSelectionTargetsClickedOnly() {
        let a = UUID()
        let b = UUID()
        let clicked = UUID()
        let selected: Set<UUID> = [a, b]

        let targets = ConversationContextMenuTargetResolver.targetIDs(clickedID: clicked, selectedIDs: selected)
        XCTAssertEqual(targets, [clicked])
    }

    func testNoSelectionUsesClicked() {
        let clicked = UUID()
        let targets = ConversationContextMenuTargetResolver.targetIDs(clickedID: clicked, selectedIDs: [])
        XCTAssertEqual(targets, [clicked])
    }
}
