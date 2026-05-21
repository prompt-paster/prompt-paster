import Foundation

struct PromptLibrary: Codable, Equatable {
    static let supportedVersion = 1

    let version: Int
    let prompts: [Prompt]

    init(version: Int = supportedVersion, prompts: [Prompt]) {
        self.version = version
        self.prompts = prompts
    }
}

struct PromptLibraryValidation: Equatable {
    let warnings: [PromptLibraryWarning]
}

enum PromptLibraryValidationError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case missingID(index: Int)
    case invalidID(String)
    case missingTitle(id: String)
    case missingBody(id: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported prompt library version \(version)."
        case .missingID(let index):
            "Prompt at index \(index) is missing an id."
        case .invalidID(let id):
            "Prompt id '\(id)' must be a lowercase slug using letters, numbers, and hyphens."
        case .missingTitle(let id):
            "Prompt '\(id)' is missing a title."
        case .missingBody(let id):
            "Prompt '\(id)' is missing a body."
        }
    }
}

enum PromptLibraryWarning: Equatable {
    case duplicateID(id: String, skippedIndexes: [Int])
    case shortcutConflict(shortcut: String, promptIDs: [String])
}

struct PromptLibraryLoadResult: Equatable {
    let library: PromptLibrary
    let validation: PromptLibraryValidation
}

extension PromptLibrary {
    func validated() throws -> PromptLibraryValidation {
        try validatedForLoading().validation
    }

    func validatedForLoading() throws -> PromptLibraryLoadResult {
        guard version == Self.supportedVersion else {
            throw PromptLibraryValidationError.unsupportedVersion(version)
        }

        var ids = Set<String>()
        var duplicateIndexesByID: [String: [Int]] = [:]
        var shortcutsByValue: [String: [String]] = [:]
        var loadablePrompts: [Prompt] = []

        for (index, prompt) in prompts.enumerated() {
            let trimmedID = prompt.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                throw PromptLibraryValidationError.missingID(index: index)
            }
            guard trimmedID == prompt.id, Self.isValidSlug(prompt.id) else {
                throw PromptLibraryValidationError.invalidID(prompt.id)
            }
            guard !prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PromptLibraryValidationError.missingTitle(id: prompt.id)
            }
            guard !prompt.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PromptLibraryValidationError.missingBody(id: prompt.id)
            }
            guard ids.insert(trimmedID).inserted else {
                duplicateIndexesByID[trimmedID, default: []].append(index)
                continue
            }

            if let shortcut = prompt.shortcut?.trimmingCharacters(in: .whitespacesAndNewlines),
               !shortcut.isEmpty {
                shortcutsByValue[shortcut.uppercased(), default: []].append(trimmedID)
            }

            loadablePrompts.append(prompt)
        }

        let duplicateWarnings = duplicateIndexesByID
            .map { PromptLibraryWarning.duplicateID(id: $0.key, skippedIndexes: $0.value) }
            .sorted { lhs, rhs in
                switch (lhs, rhs) {
                case (.duplicateID(let left, _), .duplicateID(let right, _)):
                    left < right
                case (.duplicateID, .shortcutConflict):
                    true
                case (.shortcutConflict, .duplicateID):
                    false
                case (.shortcutConflict(let left, _), .shortcutConflict(let right, _)):
                    left < right
                }
            }

        let shortcutWarnings = shortcutsByValue
            .filter { $0.value.count > 1 }
            .map { PromptLibraryWarning.shortcutConflict(shortcut: $0.key, promptIDs: $0.value) }
            .sorted { lhs, rhs in
                switch (lhs, rhs) {
                case (.duplicateID(let left, _), .duplicateID(let right, _)):
                    left < right
                case (.duplicateID, .shortcutConflict):
                    true
                case (.shortcutConflict, .duplicateID):
                    false
                case (.shortcutConflict(let left, _), .shortcutConflict(let right, _)):
                    left < right
                }
            }

        let validation = PromptLibraryValidation(warnings: duplicateWarnings + shortcutWarnings)
        return PromptLibraryLoadResult(
            library: PromptLibrary(version: version, prompts: loadablePrompts),
            validation: validation
        )
    }

    private static func isValidSlug(_ value: String) -> Bool {
        value.range(
            of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#,
            options: .regularExpression
        ) != nil
    }
}
