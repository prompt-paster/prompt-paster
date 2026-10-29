import Foundation

enum PromptContentExtractor {
    static func extract(_ text: String, mode: GitHubSourceContent) throws -> String {
        guard mode == .pasteReadyBlock else { return text }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var headings: [Int] = []
        var fence: (character: Character, count: Int)?
        for index in lines.indices {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if let active = fence {
                if line.count >= active.count, line.allSatisfy({ $0 == active.character }) { fence = nil }
                continue
            }
            if line.lowercased() == "## paste-ready prompt" { headings.append(index) }
            if let character = line.first, character == "`" || character == "~" {
                let count = line.prefix(while: { $0 == character }).count
                if count >= 3 { fence = (character, count) }
            }
        }
        guard headings.count == 1, let heading = headings.first else {
            throw ExtractionError.missingOrAmbiguousBlock
        }
        var opening: (index: Int, character: Character, count: Int)?
        for index in lines.indices where index > heading {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard opening == nil else { break }
            if line.isEmpty { continue }
            guard let character = line.first, character == "`" || character == "~" else {
                throw ExtractionError.missingOrAmbiguousBlock
            }
            let count = line.prefix(while: { $0 == character }).count
            let language = line.dropFirst(count).trimmingCharacters(in: .whitespaces).lowercased()
            guard count >= 3, ["", "text", "txt", "plaintext", "markdown", "md"].contains(language) else {
                throw ExtractionError.missingOrAmbiguousBlock
            }
            opening = (index, character, count)
        }
        guard let opening else { throw ExtractionError.missingOrAmbiguousBlock }
        for index in lines.indices where index > opening.index {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.count >= opening.count, line.allSatisfy({ $0 == opening.character }) {
                let body = lines[(opening.index + 1)..<index].joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { throw ExtractionError.missingOrAmbiguousBlock }
                return body
            }
        }
        throw ExtractionError.missingOrAmbiguousBlock
    }

    enum ExtractionError: Error, LocalizedError {
        case missingOrAmbiguousBlock
        var errorDescription: String? {
            "Expected one nonempty fenced text block immediately after '## Paste-Ready Prompt'. Check the source file or select Entire file."
        }
    }
}
