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

struct PromptOverlayShortcutAssignment: Equatable {
    let promptID: Prompt.ID
    let key: String

    var badge: String {
        key.uppercased()
    }
}

struct PromptOverlayState {
    static let promptCardMinimumWidth: CGFloat = 240
    static let promptCardSpacing: CGFloat = 10
    static let promptCardMaximumColumnCount = 6

    private struct SpatialShortcutKey {
        let key: String
        let row: Int
        let column: Double
    }

    static func visiblePrompts(
        prompts: [Prompt],
        query: String,
        selectedCategoryID: String,
        orderingMode: PromptOrderingMode = .libraryOrder,
        usageStats: [Prompt.ID: PromptUsageStats] = [:]
    ) -> [Prompt] {
        let filteredPrompts = PromptSearch.filteredPrompts(
            prompts,
            query: query,
            categoryID: selectedCategoryID
        )
        return orderedPrompts(
            filteredPrompts,
            query: query,
            orderingMode: orderingMode,
            usageStats: usageStats
        )
    }

    static func orderedPrompts(
        _ prompts: [Prompt],
        query: String = "",
        orderingMode: PromptOrderingMode,
        usageStats: [Prompt.ID: PromptUsageStats]
    ) -> [Prompt] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard orderingMode != .libraryOrder || !normalizedQuery.isEmpty else {
            return prompts
        }

        let libraryIndexesByID = Dictionary(
            uniqueKeysWithValues: prompts.enumerated().map { ($0.element.id, $0.offset) }
        )

        return prompts.sorted { lhs, rhs in
            if !normalizedQuery.isEmpty {
                let lhsRelevance = PromptSearch.searchRelevanceRank(for: lhs, query: normalizedQuery) ?? Int.max
                let rhsRelevance = PromptSearch.searchRelevanceRank(for: rhs, query: normalizedQuery) ?? Int.max
                if lhsRelevance != rhsRelevance {
                    return lhsRelevance < rhsRelevance
                }
            }

            let lhsStats = usageStats[lhs.id] ?? .empty
            let rhsStats = usageStats[rhs.id] ?? .empty

            switch orderingMode {
            case .libraryOrder:
                break
            case .mostUsed:
                if lhsStats.copyCount != rhsStats.copyCount {
                    return lhsStats.copyCount > rhsStats.copyCount
                }
                if lhsStats.lastCopiedAt != rhsStats.lastCopiedAt {
                    return moreRecent(lhsStats.lastCopiedAt, than: rhsStats.lastCopiedAt)
                }
            case .recentlyUsed:
                if lhsStats.lastCopiedAt != rhsStats.lastCopiedAt {
                    return moreRecent(lhsStats.lastCopiedAt, than: rhsStats.lastCopiedAt)
                }
                if lhsStats.copyCount != rhsStats.copyCount {
                    return lhsStats.copyCount > rhsStats.copyCount
                }
            }

            return (libraryIndexesByID[lhs.id] ?? 0) < (libraryIndexesByID[rhs.id] ?? 0)
        }
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
            3
        case ...180:
            4
        case ...320:
            6
        default:
            9
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

        let metadataWeight = prompt.title.count + (prompt.category?.count ?? 0)
        let previewWeight = min(prompt.body.count, previewCharacterLimit)
        let shouldUseWideCard = metadataWeight >= 72
            || previewWeight >= 260

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

    static func shortcutAssignments(
        for prompts: [Prompt],
        availableColumns: Int,
        previewCharacterLimit: Int,
        mode: PromptSelectionShortcutMode
    ) -> [PromptOverlayShortcutAssignment] {
        switch mode {
        case .numbers:
            return prompts.prefix(9).enumerated().map { index, prompt in
                PromptOverlayShortcutAssignment(promptID: prompt.id, key: "\(index + 1)")
            }
        case .spatialLetters:
            return spatialLetterShortcutAssignments(
                for: prompts,
                availableColumns: availableColumns,
                previewCharacterLimit: previewCharacterLimit
            )
        }
    }

    static func promptIDForShortcut(
        _ key: String,
        assignments: [PromptOverlayShortcutAssignment]
    ) -> Prompt.ID? {
        let normalizedKey = key.lowercased()
        return assignments.first { $0.key == normalizedKey }?.promptID
    }

    private static func spatialLetterShortcutAssignments(
        for prompts: [Prompt],
        availableColumns: Int,
        previewCharacterLimit: Int
    ) -> [PromptOverlayShortcutAssignment] {
        let layout = promptCardLayout(
            for: prompts,
            availableColumns: availableColumns,
            previewCharacterLimit: previewCharacterLimit
        )
        guard !layout.isEmpty else {
            return []
        }

        let maxRow = layout.map(\.row).max() ?? 0
        var usedKeys = Set<String>()

        return layout.compactMap { item in
            let candidates = spatialLetterCandidatesByKeyboardDistance(
                for: item,
                maxRow: maxRow,
                availableColumns: max(1, availableColumns)
            )
            guard let key = candidates.first(where: { !usedKeys.contains($0) }) else {
                return nil
            }
            usedKeys.insert(key)
            return PromptOverlayShortcutAssignment(promptID: item.promptID, key: key)
        }
    }

    private static func spatialLetterCandidatesByKeyboardDistance(
        for item: PromptOverlayCardLayoutItem,
        maxRow: Int,
        availableColumns: Int
    ) -> [String] {
        let preferredKeyboardRow = spatialKeyboardRow(for: item.row, maxRow: maxRow)
        let keyboardRows = spatialKeyboardRows()
        let preferredKeys = keyboardRows.filter { $0.row == preferredKeyboardRow }

        let denominator = max(1, availableColumns - 1)
        let normalizedColumn = (item.centerColumn - 0.5) / Double(denominator)
        let clampedColumn = min(1, max(0, normalizedColumn))
        let targetColumn = targetKeyboardColumn(
            normalizedColumn: clampedColumn,
            keys: preferredKeys
        )

        return keyboardRows
            .sorted { lhs, rhs in
                let lhsDistance = spatialDistance(
                    from: lhs,
                    preferredRow: preferredKeyboardRow,
                    targetColumn: targetColumn
                )
                let rhsDistance = spatialDistance(
                    from: rhs,
                    preferredRow: preferredKeyboardRow,
                    targetColumn: targetColumn
                )
                if lhsDistance == rhsDistance {
                    let lhsIndex = keyboardRows.firstIndex(where: { $0.key == lhs.key }) ?? 0
                    let rhsIndex = keyboardRows.firstIndex(where: { $0.key == rhs.key }) ?? 0
                    return lhsIndex < rhsIndex
                }
                return lhsDistance < rhsDistance
            }
            .map(\.key)
    }

    private static func spatialKeyboardRow(for row: Int, maxRow: Int) -> Int {
        if maxRow == 0 {
            return 1
        }

        if row == 0 {
            return 0
        }

        if row == maxRow, maxRow >= 2 {
            return 2
        }

        return 1
    }

    private static func spatialKeyboardRows() -> [SpatialShortcutKey] {
        [
            SpatialShortcutKey(key: "r", row: 0, column: 0),
            SpatialShortcutKey(key: "t", row: 0, column: 1),
            SpatialShortcutKey(key: "y", row: 0, column: 2),
            SpatialShortcutKey(key: "u", row: 0, column: 3),
            SpatialShortcutKey(key: "i", row: 0, column: 4),
            SpatialShortcutKey(key: "f", row: 1, column: 0),
            SpatialShortcutKey(key: "g", row: 1, column: 1),
            SpatialShortcutKey(key: "h", row: 1, column: 2),
            SpatialShortcutKey(key: "j", row: 1, column: 3),
            SpatialShortcutKey(key: "k", row: 1, column: 4),
            SpatialShortcutKey(key: "l", row: 1, column: 5),
            SpatialShortcutKey(key: "v", row: 2, column: 0),
            SpatialShortcutKey(key: "b", row: 2, column: 1),
            SpatialShortcutKey(key: "n", row: 2, column: 2),
            SpatialShortcutKey(key: "m", row: 2, column: 3)
        ]
    }

    private static func targetKeyboardColumn(
        normalizedColumn: Double,
        keys: [SpatialShortcutKey]
    ) -> Double {
        let columns = keys.map(\.column)
        let minimumColumn = columns.min() ?? 0
        let maximumColumn = columns.max() ?? minimumColumn
        return minimumColumn + (normalizedColumn * (maximumColumn - minimumColumn))
    }

    private static func spatialDistance(
        from key: SpatialShortcutKey,
        preferredRow: Int,
        targetColumn: Double
    ) -> Double {
        let rowDistance = abs(Double(key.row - preferredRow)) * 3
        let columnDistance = abs(key.column - targetColumn)
        return rowDistance + columnDistance
    }

    static func promptCardMinimumHeight(
        for prompt: Prompt,
        previewCharacterLimit: Int
    ) -> CGFloat {
        let hasLongPreview = min(prompt.body.count, previewCharacterLimit) > 140
        let hasLongTitle = prompt.title.count > 42

        return switch (hasLongPreview, hasLongTitle) {
        case (true, true):
            142
        case (true, false):
            126
        case (false, true):
            118
        case (false, false):
            104
        }
    }

    private static func moreRecent(_ lhs: Date?, than rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return false
        }
    }
}
