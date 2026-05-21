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
    case missingTitle(id: String)
    case missingBody(id: String)
    case duplicateID(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported prompt library version \(version)."
        case .missingID(let index):
            "Prompt at index \(index) is missing an id."
        case .missingTitle(let id):
            "Prompt '\(id)' is missing a title."
        case .missingBody(let id):
            "Prompt '\(id)' is missing a body."
        case .duplicateID(let id):
            "Prompt id '\(id)' is duplicated."
        }
    }
}

enum PromptLibraryWarning: Equatable {
    case shortcutConflict(shortcut: String, promptIDs: [String])
}

extension PromptLibrary {
    func validated() throws -> PromptLibraryValidation {
        guard version == Self.supportedVersion else {
            throw PromptLibraryValidationError.unsupportedVersion(version)
        }

        var ids = Set<String>()
        var shortcutsByValue: [String: [String]] = [:]

        for (index, prompt) in prompts.enumerated() {
            let trimmedID = prompt.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else {
                throw PromptLibraryValidationError.missingID(index: index)
            }
            guard !prompt.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PromptLibraryValidationError.missingTitle(id: prompt.id)
            }
            guard !prompt.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PromptLibraryValidationError.missingBody(id: prompt.id)
            }
            guard ids.insert(prompt.id).inserted else {
                throw PromptLibraryValidationError.duplicateID(prompt.id)
            }

            if let shortcut = prompt.shortcut?.trimmingCharacters(in: .whitespacesAndNewlines),
               !shortcut.isEmpty {
                shortcutsByValue[shortcut.uppercased(), default: []].append(prompt.id)
            }
        }

        let warnings = shortcutsByValue
            .filter { $0.value.count > 1 }
            .map { PromptLibraryWarning.shortcutConflict(shortcut: $0.key, promptIDs: $0.value) }
            .sorted { lhs, rhs in
                switch (lhs, rhs) {
                case (.shortcutConflict(let left, _), .shortcutConflict(let right, _)):
                    left < right
                }
            }

        return PromptLibraryValidation(warnings: warnings)
    }
}
