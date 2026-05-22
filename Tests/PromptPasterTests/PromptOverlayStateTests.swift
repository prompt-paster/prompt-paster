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

    func testStatusMessagesIncludeCopyFailureAfterLibraryWarnings() {
        let messages = PromptOverlayState.statusMessages(
            message: "Reloaded 3 prompts.",
            validation: PromptLibraryValidation(warnings: [
                .shortcutConflict(shortcut: "1", promptIDs: ["first", "second"])
            ]),
            copyStatusMessage: "Could not copy \"First\". Clipboard write failed."
        )

        XCTAssertEqual(messages, [
            "Reloaded 3 prompts.",
            "Library loaded with 1 warning.",
            "Could not copy \"First\". Clipboard write failed."
        ])
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

    func testPreviewTextTruncatesToConfiguredCharacterLimit() {
        let body = "1234567890abcdef"

        XCTAssertEqual(PromptOverlayState.previewText(for: body, characterLimit: 10), "1234567...")
        XCTAssertEqual(PromptOverlayState.previewText(for: body, characterLimit: 16), body)
    }

    func testPreviewLineLimitScalesWithCharacterLimit() {
        XCTAssertEqual(PromptOverlayState.previewLineLimit(for: 40), 2)
        XCTAssertEqual(PromptOverlayState.previewLineLimit(for: 120), 3)
        XCTAssertEqual(PromptOverlayState.previewLineLimit(for: 260), 5)
        XCTAssertEqual(PromptOverlayState.previewLineLimit(for: 600), 7)
    }

    func testPromptCardColumnCountAdaptsToAvailableWidth() {
        XCTAssertEqual(PromptOverlayState.promptCardColumnCount(for: 470), 1)
        XCTAssertEqual(PromptOverlayState.promptCardColumnCount(for: 620), 2)
        XCTAssertEqual(PromptOverlayState.promptCardColumnCount(for: 1_180), 4)
        XCTAssertEqual(PromptOverlayState.promptCardColumnCount(for: 1_560), 6)
        XCTAssertEqual(PromptOverlayState.promptCardColumnCount(for: 2_400), 6)
    }

    func testPromptCardSpanKeepsSmallLayoutsSingleColumn() {
        let longPrompt = Prompt(
            id: "long",
            title: "A long prompt that needs more room in a dense scanning layout",
            category: "Review",
            body: String(repeating: "Body ", count: 90),
            tags: ["swift", "review", "macos", "overlay"]
        )

        XCTAssertEqual(
            PromptOverlayState.promptCardColumnSpan(
                for: longPrompt,
                availableColumns: 2,
                previewCharacterLimit: 260
            ),
            1
        )
        XCTAssertEqual(
            PromptOverlayState.promptCardColumnSpan(
                for: longPrompt,
                availableColumns: 3,
                previewCharacterLimit: 260
            ),
            2
        )
    }

    func testPromptCardMinimumHeightScalesWithContentDensity() {
        let compactPrompt = Prompt(id: "compact", title: "Compact", category: nil, body: "Short")
        let densePrompt = Prompt(
            id: "dense",
            title: "Longer prompt title that should receive more vertical room",
            category: "Planning",
            body: String(repeating: "Preview ", count: 30),
            tags: ["scope", "handoff"]
        )

        XCTAssertEqual(
            PromptOverlayState.promptCardMinimumHeight(
                for: compactPrompt,
                previewCharacterLimit: 80
            ),
            126
        )
        XCTAssertEqual(
            PromptOverlayState.promptCardMinimumHeight(
                for: densePrompt,
                previewCharacterLimit: 260
            ),
            188
        )
    }

    func testPromptCardLayoutTracksRowsColumnsAndSpans() {
        let longPrompt = Prompt(
            id: "wide",
            title: "A long prompt that should span two columns",
            category: "Review",
            body: String(repeating: "Body ", count: 90),
            tags: ["swift", "review", "macos", "overlay"]
        )
        let compactPrompts = [
            Prompt(id: "one", title: "One", category: nil, body: "One"),
            Prompt(id: "two", title: "Two", category: nil, body: "Two")
        ]

        XCTAssertEqual(
            PromptOverlayState.promptCardLayout(
                for: [longPrompt] + compactPrompts,
                availableColumns: 3,
                previewCharacterLimit: 260
            ),
            [
                PromptOverlayCardLayoutItem(
                    promptID: "wide",
                    index: 0,
                    row: 0,
                    column: 0,
                    columnSpan: 2
                ),
                PromptOverlayCardLayoutItem(
                    promptID: "one",
                    index: 1,
                    row: 0,
                    column: 2,
                    columnSpan: 1
                ),
                PromptOverlayCardLayoutItem(
                    promptID: "two",
                    index: 2,
                    row: 1,
                    column: 0,
                    columnSpan: 1
                )
            ]
        )
    }

    func testVerticalSelectionMovesByVisualGridRows() {
        let gridPrompts = [
            Prompt(id: "one", title: "One", category: nil, body: "One"),
            Prompt(id: "two", title: "Two", category: nil, body: "Two"),
            Prompt(id: "three", title: "Three", category: nil, body: "Three"),
            Prompt(id: "four", title: "Four", category: nil, body: "Four"),
            Prompt(id: "five", title: "Five", category: nil, body: "Five")
        ]

        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDMovingVertically(
                currentID: "two",
                visiblePrompts: gridPrompts,
                availableColumns: 3,
                previewCharacterLimit: 80,
                direction: 1
            ),
            "five"
        )
        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDMovingVertically(
                currentID: "five",
                visiblePrompts: gridPrompts,
                availableColumns: 3,
                previewCharacterLimit: 80,
                direction: -1
            ),
            "two"
        )
    }

    func testVerticalSelectionClampsAtGridEdges() {
        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDMovingVertically(
                currentID: "first",
                visiblePrompts: prompts,
                availableColumns: 3,
                previewCharacterLimit: 80,
                direction: -1
            ),
            "first"
        )
        XCTAssertEqual(
            PromptOverlayState.selectedPromptIDMovingVertically(
                currentID: "third",
                visiblePrompts: prompts,
                availableColumns: 3,
                previewCharacterLimit: 80,
                direction: 1
            ),
            "third"
        )
    }
}
