import XCTest
@testable import PromptPaster

@MainActor
final class PromptOverlayActionsTests: XCTestCase {
    private let prompts = [
        Prompt(id: "first", title: "First", category: "PR", body: "First body"),
        Prompt(id: "second", title: "Second", category: "Docs", body: "Second body"),
        Prompt(id: "third", title: "Third", category: "Docs", body: "Third body")
    ]

    func testSelectPromptAtVisibleIndexCopiesPromptBodyAndCloses() {
        let clipboard = FakeClipboard()
        var recordedPromptIDs: [Prompt.ID] = []
        let actions = PromptOverlayActions(
            clipboard: clipboard,
            recordPromptCopy: { recordedPromptIDs.append($0) }
        )

        let outcome = actions.selectPrompt(at: 1, visiblePrompts: prompts)

        XCTAssertEqual(clipboard.copiedTexts, ["Second body"])
        XCTAssertEqual(recordedPromptIDs, ["second"])
        XCTAssertEqual(outcome, PromptOverlaySelectionOutcome(
            selectedPromptID: "second",
            shouldClose: true,
            copyStatusMessage: nil
        ))
    }

    func testSelectCurrentPromptUsesCurrentSelection() {
        let clipboard = FakeClipboard()
        let actions = PromptOverlayActions(clipboard: clipboard)

        let outcome = actions.selectCurrentPrompt(
            selectedPromptID: "third",
            visiblePrompts: prompts
        )

        XCTAssertEqual(clipboard.copiedTexts, ["Third body"])
        XCTAssertEqual(outcome?.selectedPromptID, "third")
        XCTAssertEqual(outcome?.shouldClose, true)
    }

    func testInvalidIndexDoesNotCopyOrClose() {
        let clipboard = FakeClipboard()
        let actions = PromptOverlayActions(clipboard: clipboard)

        let outcome = actions.selectPrompt(at: 8, visiblePrompts: prompts)

        XCTAssertNil(outcome)
        XCTAssertEqual(clipboard.copiedTexts, [])
    }

    func testMissingCurrentSelectionDoesNotCopyOrClose() {
        let clipboard = FakeClipboard()
        let actions = PromptOverlayActions(clipboard: clipboard)

        let outcome = actions.selectCurrentPrompt(
            selectedPromptID: "missing",
            visiblePrompts: prompts
        )

        XCTAssertNil(outcome)
        XCTAssertEqual(clipboard.copiedTexts, [])
    }

    func testCopyFailureKeepsOverlayOpenWithStatusMessage() {
        let clipboard = FakeClipboard(error: ClipboardServiceError.writeFailed)
        var recordedPromptIDs: [Prompt.ID] = []
        let actions = PromptOverlayActions(
            clipboard: clipboard,
            recordPromptCopy: { recordedPromptIDs.append($0) }
        )

        let outcome = actions.selectPrompt(at: 0, visiblePrompts: prompts)

        XCTAssertEqual(clipboard.copiedTexts, ["First body"])
        XCTAssertEqual(recordedPromptIDs, [])
        XCTAssertEqual(outcome, PromptOverlaySelectionOutcome(
            selectedPromptID: "first",
            shouldClose: false,
            copyStatusMessage: "Could not copy \"First\". Clipboard write failed."
        ))
    }
}

@MainActor
private final class FakeClipboard: ClipboardCopying {
    var copiedTexts: [String] = []

    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func copyPlainText(_ text: String) throws {
        copiedTexts.append(text)

        if let error {
            throw error
        }
    }
}
