import XCTest
@testable import PromptPaster

final class PromptOverlayStateTests: XCTestCase {
    private let prompts = [
        Prompt(id: "first", title: "First", category: "PR", body: "First body"),
        Prompt(id: "second", title: "Second", category: "Docs", body: "Second body"),
        Prompt(id: "third", title: "Third", category: "Docs", body: "Third body")
    ]

    func testInvalidLibraryErrorTakesPrimaryEmptyState() {
        let emptyState = PromptOverlayState.emptyState(
            prompts: [],
            visiblePrompts: [],
            query: "",
            lastErrorMessage: "The data could not be read."
        )

        XCTAssertEqual(emptyState?.title, "Prompt library could not load")
        XCTAssertTrue(emptyState?.detail.contains("The data could not be read.") == true)
    }

    func testEmptyLibraryAndEmptySearchHaveDifferentStates() {
        XCTAssertEqual(
            PromptOverlayState.emptyState(
                prompts: [],
                visiblePrompts: [],
                query: "",
                lastErrorMessage: nil
            ),
            PromptOverlayEmptyState(
                title: "No prompts loaded",
                detail: "Use Reload Library from the menu after adding prompts to prompts.json."
            )
        )

        XCTAssertEqual(
            PromptOverlayState.emptyState(
                prompts: prompts,
                visiblePrompts: [],
                query: "missing",
                lastErrorMessage: nil
            ),
            PromptOverlayEmptyState(
                title: "No search results",
                detail: "Try a different title, category, tag, or body term."
            )
        )
    }

    func testSelectionMovementClampsToVisiblePrompts() {
        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDMoving(
                currentID: "first",
                visiblePrompts: prompts,
                offset: 1
            ),
            "second"
        )
        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDMoving(
                currentID: "third",
                visiblePrompts: prompts,
                offset: 1
            ),
            "third"
        )
        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDMoving(
                currentID: "first",
                visiblePrompts: prompts,
                offset: -1
            ),
            "first"
        )
    }

    func testKeepingSelectionChoosesFirstVisibleWhenCurrentIsMissing() {
        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDKeepingVisible(
                currentID: "missing",
                visiblePrompts: prompts
            ),
            "first"
        )
        XCTAssertNil(
            PromptOverlayState.selectedPromptIDKeepingVisible(
                currentID: "first",
                visiblePrompts: []
            )
        )
    }
}
