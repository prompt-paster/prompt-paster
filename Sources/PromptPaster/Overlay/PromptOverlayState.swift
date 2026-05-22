import Foundation

struct PromptOverlayEmptyState: Equatable {
    let title: String
    let detail: String
}

struct PromptOverlayState {
    static func visiblePrompts(
        prompts: [Prompt],
        query: String,
        selectedCategoryID: String
    ) -> [Prompt] {
        PromptSearch.filteredPrompts(prompts, query: query, categoryID: selectedCategoryID)
    }

    static func statusMessages(
        message: String?,
        validation: PromptLibraryValidation?,
        acknowledgement: String?
    ) -> [String] {
        var messages: [String] = []

        if let message, !message.isEmpty {
            messages.append(message)
        }

        if let validation, !validation.warnings.isEmpty {
            messages.append("Library loaded with \(validation.warnings.count) warning\(validation.warnings.count == 1 ? "" : "s").")
        }

        if let acknowledgement {
            messages.append(acknowledgement)
        }

        return messages
    }

    static func emptyState(
        prompts: [Prompt],
        visiblePrompts: [Prompt],
        query: String,
        lastErrorMessage: String?
    ) -> PromptOverlayEmptyState? {
        if let lastErrorMessage {
            return PromptOverlayEmptyState(
                title: "Prompt library could not load",
                detail: "Fix prompts.json, then use Reload Library. \(lastErrorMessage)"
            )
        }

        if prompts.isEmpty {
            return PromptOverlayEmptyState(
                title: "No prompts loaded",
                detail: "Use Reload Library from the menu after adding prompts to prompts.json."
            )
        }

        if visiblePrompts.isEmpty {
            let detail = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No prompts match this category."
                : "Try a different title, category, tag, or body term."
            return PromptOverlayEmptyState(title: "No search results", detail: detail)
        }

        return nil
    }

    static func selectedPromptIDKeepingVisible(
        currentID: Prompt.ID?,
        visiblePrompts: [Prompt]
    ) -> Prompt.ID? {
        guard !visiblePrompts.isEmpty else {
            return nil
        }

        if let currentID, visiblePrompts.contains(where: { $0.id == currentID }) {
            return currentID
        }

        return visiblePrompts.first?.id
    }

    static func selectedPromptIDMoving(
        currentID: Prompt.ID?,
        visiblePrompts: [Prompt],
        offset: Int
    ) -> Prompt.ID? {
        guard !visiblePrompts.isEmpty else {
            return nil
        }

        let currentIndex = currentID.flatMap { id in
            visiblePrompts.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), visiblePrompts.count - 1)
        return visiblePrompts[nextIndex].id
    }
}
