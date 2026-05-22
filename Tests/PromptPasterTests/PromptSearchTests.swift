import XCTest
@testable import PromptPaster

final class PromptSearchTests: XCTestCase {
    private let prompts = [
        Prompt(
            id: "merge-check",
            title: "Merge Check",
            category: "PR",
            body: "Wait for CI and inspect failures.",
            tags: ["merge", "ci"]
        ),
        Prompt(
            id: "handoff",
            title: "New Agent Handoff",
            category: "Handoff",
            body: "Include branch, files, blockers, and validation.",
            tags: ["agent"]
        ),
        Prompt(
            id: "docs-intro",
            title: "Technical Wiki Intro",
            category: "Docs",
            body: "Write architecture and setup notes.",
            tags: ["wiki"]
        )
    ]

    func testCategoriesIncludeAllAndLoadedPromptCategories() {
        XCTAssertEqual(PromptSearch.categories(for: prompts).map(\.title), ["All", "Docs", "Handoff", "PR"])
    }

    func testCategoriesDeduplicateByNormalizedDisplayName() {
        let prompts = [
            Prompt(id: "one", title: "One", category: "PR", body: "Body"),
            Prompt(id: "two", title: "Two", category: " pr ", body: "Body"),
            Prompt(id: "three", title: "Three", category: "Docs", body: "Body")
        ]

        XCTAssertEqual(PromptSearch.categories(for: prompts).map(\.title), ["All", "Docs", "PR"])
    }

    func testFiltersAcrossTitleCategoryTagsAndBody() {
        XCTAssertEqual(
            PromptSearch.filteredPrompts(prompts, query: "merge", categoryID: PromptCategoryFilter.all.id).map(\.id),
            ["merge-check"]
        )
        XCTAssertEqual(
            PromptSearch.filteredPrompts(prompts, query: "handoff", categoryID: PromptCategoryFilter.all.id).map(\.id),
            ["handoff"]
        )
        XCTAssertEqual(
            PromptSearch.filteredPrompts(prompts, query: "wiki", categoryID: PromptCategoryFilter.all.id).map(\.id),
            ["docs-intro"]
        )
        XCTAssertEqual(
            PromptSearch.filteredPrompts(prompts, query: "validation", categoryID: PromptCategoryFilter.all.id).map(\.id),
            ["handoff"]
        )
    }

    func testFiltersByCategoryAndKeepsConfiguredOrder() {
        let prCategoryID = PromptSearch.categories(for: prompts).first { $0.title == "PR" }?.id

        XCTAssertEqual(
            PromptSearch.filteredPrompts(prompts, query: "", categoryID: prCategoryID ?? "").map(\.id),
            ["merge-check"]
        )
        XCTAssertEqual(
            PromptSearch.filteredPrompts(prompts, query: "", categoryID: PromptCategoryFilter.all.id).map(\.id),
            ["merge-check", "handoff", "docs-intro"]
        )
    }
}
