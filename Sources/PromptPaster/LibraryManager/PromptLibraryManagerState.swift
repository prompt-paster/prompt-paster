import Foundation

struct PromptLibraryDraft: Equatable {
    var title: String
    var body: String
    var category: String
    var tagsText: String

    init(prompt: Prompt) {
        title = prompt.title
        body = prompt.body
        category = prompt.category ?? ""
        tagsText = prompt.tags.joined(separator: ", ")
    }

    func updatedPrompt(from prompt: Prompt) throws -> Prompt {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw PromptLibraryManagerError.emptyTitle
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            throw PromptLibraryManagerError.emptyBody
        }

        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Prompt(
            id: prompt.id,
            title: trimmedTitle,
            category: trimmedCategory.isEmpty ? nil : trimmedCategory,
            body: trimmedBody,
            shortcut: prompt.shortcut,
            tags: tags,
            updatedAt: prompt.updatedAt
        )
    }
}

enum PromptLibraryManagerError: Error, Equatable, LocalizedError {
    case emptyTitle
    case emptyBody
    case promptNotFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Title is required."
        case .emptyBody:
            "Body is required."
        case .promptNotFound(let id):
            "Prompt '\(id)' could not be found."
        }
    }
}

struct PromptLibraryManagerState {
    static let allTagID = "__all_tags__"

    static func categories(for prompts: [Prompt]) -> [PromptCategoryFilter] {
        PromptSearch.categories(for: prompts)
    }

    static func tags(for prompts: [Prompt]) -> [PromptCategoryFilter] {
        let tags = Set(prompts.flatMap(\.tags).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { PromptCategoryFilter(id: tagID(for: $0), title: $0) }
        return [PromptCategoryFilter(id: allTagID, title: "All Tags")] + tags
    }

    static func filteredPrompts(
        _ prompts: [Prompt],
        query: String,
        categoryID: String,
        tagID selectedTagID: String
    ) -> [Prompt] {
        PromptSearch.filteredPrompts(
            prompts,
            query: query,
            categoryID: categoryID
        )
        .filter { prompt in
            selectedTagID == allTagID
                || prompt.tags.contains { tagID(for: $0) == selectedTagID }
        }
    }

    static func library(
        byUpdatingPromptID promptID: Prompt.ID,
        in library: PromptLibrary,
        with draft: PromptLibraryDraft
    ) throws -> PromptLibrary {
        guard let promptIndex = library.prompts.firstIndex(where: { $0.id == promptID }) else {
            throw PromptLibraryManagerError.promptNotFound(promptID)
        }

        var prompts = library.prompts
        prompts[promptIndex] = try draft.updatedPrompt(from: prompts[promptIndex])
        return PromptLibrary(version: library.version, prompts: prompts)
    }

    private static func tagID(for value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
