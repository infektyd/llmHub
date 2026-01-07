import XCTest

@testable import llmHub

final class ConversationContextMenuTargetResolverTests: XCTestCase {

    func testMultiSelectionUsesSelection() {
        let a = UUID()
        let b = UUID()
        let clicked = UUID()

        let targets = ConversationContextMenuTargetResolver.targetIDs(clickedID: clicked, selectedIDs: [a, b])
        XCTAssertEqual(targets, [a, b])
    }

    func testSingleSelectionUsesClicked() {
        let clicked = UUID()
        let targets = ConversationContextMenuTargetResolver.targetIDs(clickedID: clicked, selectedIDs: [clicked])
        XCTAssertEqual(targets, [clicked])
    }

    func testNoSelectionUsesClicked() {
        let clicked = UUID()
        let targets = ConversationContextMenuTargetResolver.targetIDs(clickedID: clicked, selectedIDs: [])
        XCTAssertEqual(targets, [clicked])
    }
}
