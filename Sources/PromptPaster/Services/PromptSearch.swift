import Foundation

struct PromptCategoryFilter: Equatable, Hashable, Identifiable {
    static let all = PromptCategoryFilter(id: "__all__", title: "All")

    let id: String
    let title: String
}

struct PromptSearch {
    static let allCategory = "All"

    static func categories(for prompts: [Prompt]) -> [PromptCategoryFilter] {
        let categoriesByID = prompts.reduce(into: [String: String]()) { partialResult, prompt in
            let trimmed = prompt.category?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else {
                return
            }
            let id = categoryID(for: trimmed)
            if partialResult[id] == nil {
                partialResult[id] = trimmed
            }
        }

        let categories = categoriesByID
            .map { PromptCategoryFilter(id: $0.key, title: $0.value) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        return [.all] + categories
    }

    static func filteredPrompts(
        _ prompts: [Prompt],
        query: String,
        categoryID selectedCategoryID: String
    ) -> [Prompt] {
        let normalizedQuery = normalize(query)

        return prompts.filter { prompt in
            let matchesCategory = selectedCategoryID == PromptCategoryFilter.all.id
                || categoryID(for: prompt.category ?? "") == selectedCategoryID
            guard matchesCategory else {
                return false
            }

            guard !normalizedQuery.isEmpty else {
                return true
            }

            return searchRelevanceRank(for: prompt, normalizedQuery: normalizedQuery) != nil
        }
    }

    static func searchRelevanceRank(for prompt: Prompt, query: String) -> Int? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else {
            return 0
        }

        return searchRelevanceRank(for: prompt, normalizedQuery: normalizedQuery)
    }

    private static func searchableText(for prompt: Prompt) -> String {
        normalize(
            [
                prompt.title,
                prompt.category ?? "",
                prompt.tags.joined(separator: " "),
                prompt.body
            ].joined(separator: " ")
        )
    }

    private static func searchRelevanceRank(
        for prompt: Prompt,
        normalizedQuery: String
    ) -> Int? {
        let normalizedTitle = normalize(prompt.title)
        if normalizedTitle.hasPrefix(normalizedQuery) {
            return 0
        }

        if normalizedTitle.contains(normalizedQuery) {
            return 1
        }

        let normalizedCategory = normalize(prompt.category ?? "")
        let normalizedTags = prompt.tags.map { normalize($0) }
        if normalizedCategory.contains(normalizedQuery)
            || normalizedTags.contains(where: { $0.contains(normalizedQuery) }) {
            return 2
        }

        let normalizedBody = normalize(prompt.body)
        if normalizedBody.contains(normalizedQuery) {
            return 3
        }

        return searchableText(for: prompt).contains(normalizedQuery) ? 4 : nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func categoryID(for value: String) -> String {
        normalize(value)
    }
}
