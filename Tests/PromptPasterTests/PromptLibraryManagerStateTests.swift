import XCTest
@testable import PromptPaster

final class PromptLibraryManagerStateTests: XCTestCase {
    func testFilteredPromptsCombinesSearchCategoryAndTagFilters() {
        let prompts = [
            Prompt(id: "one", title: "Git Commit", category: "Git", body: "Create commit", tags: ["Review"]),
            Prompt(id: "two", title: "Git Review", category: "Git", body: "Review diff", tags: ["Review", "PR"]),
            Prompt(id: "three", title: "Docs", category: "Writing", body: "Write docs", tags: ["Draft"])
        ]

        let filtered = PromptLibraryManagerState.filteredPrompts(
            prompts,
            query: "review",
            categoryID: "git",
            tagID: "pr"
        )

        XCTAssertEqual(filtered.map(\.id), ["two"])
    }

    func testDraftTrimsEditableFieldsAndPreservesNonEditableMetadata() throws {
        let prompt = Prompt(
            id: "existing",
            title: "Existing",
            category: "Old",
            body: "Old body",
            shortcut: "A",
            tags: ["old"],
            updatedAt: Date(timeIntervalSince1970: 42)
        )
        var draft = PromptLibraryDraft(prompt: prompt)
        draft.title = "  New title  "
        draft.body = "  New body  "
        draft.category = "  New category  "
        draft.tagsText = " swift, , agent "

        let updated = try draft.updatedPrompt(from: prompt)

        XCTAssertEqual(updated.id, "existing")
        XCTAssertEqual(updated.title, "New title")
        XCTAssertEqual(updated.body, "New body")
        XCTAssertEqual(updated.category, "New category")
        XCTAssertEqual(updated.tags, ["swift", "agent"])
        XCTAssertEqual(updated.shortcut, "A")
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 42))
    }

    func testDraftBlocksEmptyTitleAndBody() {
        let prompt = Prompt(id: "existing", title: "Existing", body: "Body")
        var emptyTitleDraft = PromptLibraryDraft(prompt: prompt)
        emptyTitleDraft.title = " "

        XCTAssertThrowsError(try emptyTitleDraft.updatedPrompt(from: prompt)) { error in
            XCTAssertEqual(error as? PromptLibraryManagerError, .emptyTitle)
        }

        var emptyBodyDraft = PromptLibraryDraft(prompt: prompt)
        emptyBodyDraft.body = " "

        XCTAssertThrowsError(try emptyBodyDraft.updatedPrompt(from: prompt)) { error in
            XCTAssertEqual(error as? PromptLibraryManagerError, .emptyBody)
        }
    }

    func testUpdatingLibraryPreservesPromptOrderAndVersion() throws {
        let library = PromptLibrary(version: 1, prompts: [
            Prompt(id: "one", title: "One", body: "One body"),
            Prompt(id: "two", title: "Two", body: "Two body")
        ])

        var draft = PromptLibraryDraft(prompt: library.prompts[1])
        draft.title = "Updated"
        draft.body = "Updated body"

        let updated = try PromptLibraryManagerState.library(
            byUpdatingPromptID: "two",
            in: library,
            with: draft
        )

        XCTAssertEqual(updated.version, 1)
        XCTAssertEqual(updated.prompts.map(\.id), ["one", "two"])
        XCTAssertEqual(updated.prompts[1].title, "Updated")
    }
}
