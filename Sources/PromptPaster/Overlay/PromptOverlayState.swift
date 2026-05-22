import Foundation
import CoreGraphics

struct PromptOverlayEmptyState: Equatable {
    let title: String
    let detail: String
}

struct PromptOverlayCardLayoutItem: Equatable {
    let promptID: Prompt.ID
    let index: Int
    let row: Int
    let column: Int
    let columnSpan: Int

    var centerColumn: Double {
        Double(column) + (Double(columnSpan) / 2)
    }
}

struct PromptOverlayState {
    static let promptCardMinimumWidth: CGFloat = 240
    static let promptCardSpacing: CGFloat = 10
    static let promptCardMaximumColumnCount = 6

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
        copyStatusMessage: String?
    ) -> [String] {
        var messages: [String] = []

        if let message, !message.isEmpty {
            messages.append(message)
        }

        if let validation, !validation.warnings.isEmpty {
            messages.append("Library loaded with \(validation.warnings.count) warning\(validation.warnings.count == 1 ? "" : "s").")
        }

        if let copyStatusMessage {
            messages.append(copyStatusMessage)
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

    static func selectedPromptIDMovingVertically(
        currentID: Prompt.ID?,
        visiblePrompts: [Prompt],
        availableColumns: Int,
        previewCharacterLimit: Int,
        direction: Int
    ) -> Prompt.ID? {
        guard direction != 0 else {
            return currentID
        }

        let layout = promptCardLayout(
            for: visiblePrompts,
            availableColumns: availableColumns,
            previewCharacterLimit: previewCharacterLimit
        )
        guard !layout.isEmpty else {
            return nil
        }

        guard let currentID,
              let currentItem = layout.first(where: { $0.promptID == currentID })
        else {
            return layout.first?.promptID
        }

        let targetRow = currentItem.row + direction
        let targetItems = layout.filter { $0.row == targetRow }
        guard !targetItems.isEmpty else {
            return currentID
        }

        return targetItems.min { lhs, rhs in
            let lhsDistance = abs(lhs.centerColumn - currentItem.centerColumn)
            let rhsDistance = abs(rhs.centerColumn - currentItem.centerColumn)
            if lhsDistance == rhsDistance {
                return lhs.index < rhs.index
            }
            return lhsDistance < rhsDistance
        }?.promptID
    }

    static func previewText(for body: String, characterLimit: Int) -> String {
        guard body.count > characterLimit else {
            return body
        }

        let truncationMarker = "..."
        let prefixLength = max(0, characterLimit - truncationMarker.count)
        return String(body.prefix(prefixLength)) + truncationMarker
    }

    static func previewLineLimit(for characterLimit: Int) -> Int {
        switch characterLimit {
        case ...80:
            2
        case ...180:
            3
        case ...320:
            5
        default:
            7
        }
    }

    static func promptCardColumnCount(for availableWidth: CGFloat) -> Int {
        let widthWithTrailingSpacing = availableWidth + promptCardSpacing
        let cardWidthWithSpacing = promptCardMinimumWidth + promptCardSpacing
        let columnCount = Int(floor(widthWithTrailingSpacing / cardWidthWithSpacing))
        return min(promptCardMaximumColumnCount, max(1, columnCount))
    }

    static func promptCardColumnSpan(
        for prompt: Prompt,
        availableColumns: Int,
        previewCharacterLimit: Int
    ) -> Int {
        guard availableColumns >= 3 else {
            return 1
        }

        let metadataWeight = prompt.title.count
            + (prompt.category?.count ?? 0)
            + prompt.tags.prefix(5).reduce(0) { $0 + $1.count }
        let previewWeight = min(prompt.body.count, previewCharacterLimit)
        let shouldUseWideCard = metadataWeight >= 72
            || previewWeight >= 220
            || prompt.tags.count >= 4

        return shouldUseWideCard ? 2 : 1
    }

    static func promptCardLayout(
        for prompts: [Prompt],
        availableColumns: Int,
        previewCharacterLimit: Int
    ) -> [PromptOverlayCardLayoutItem] {
        let columnCount = max(1, availableColumns)
        var row = 0
        var column = 0

        return prompts.enumerated().map { index, prompt in
            let columnSpan = min(
                columnCount,
                promptCardColumnSpan(
                    for: prompt,
                    availableColumns: columnCount,
                    previewCharacterLimit: previewCharacterLimit
                )
            )

            if column > 0, column + columnSpan > columnCount {
                row += 1
                column = 0
            }

            let item = PromptOverlayCardLayoutItem(
                promptID: prompt.id,
                index: index,
                row: row,
                column: column,
                columnSpan: columnSpan
            )
            column += columnSpan
            if column >= columnCount {
                row += 1
                column = 0
            }
            return item
        }
    }

    static func promptCardMinimumHeight(
        for prompt: Prompt,
        previewCharacterLimit: Int
    ) -> CGFloat {
        let hasTags = !prompt.tags.isEmpty
        let hasLongPreview = min(prompt.body.count, previewCharacterLimit) > 140
        let hasLongTitle = prompt.title.count > 42

        return switch (hasTags, hasLongPreview || hasLongTitle) {
        case (true, true):
            188
        case (true, false):
            164
        case (false, true):
            150
        case (false, false):
            126
        }
    }
}
