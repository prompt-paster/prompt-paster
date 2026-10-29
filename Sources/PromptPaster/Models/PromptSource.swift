import Foundation

enum GitHubSourceAuthentication: String, Codable, CaseIterable, Identifiable {
    case storedToken
    case githubCLI
    case anonymous

    var id: String { rawValue }
    var title: String {
        switch self {
        case .storedToken: "App token (Keychain)"
        case .githubCLI: "GitHub CLI sign-in"
        case .anonymous: "Public repository"
        }
    }
}

enum GitHubSourceContent: String, Codable, CaseIterable, Identifiable {
    case wholeFile
    case pasteReadyBlock

    var id: String { rawValue }
    var title: String {
        switch self {
        case .wholeFile: "Entire file"
        case .pasteReadyBlock: "Paste-ready prompt block"
        }
    }
}

/// A single Markdown or plain-text file fetched from GitHub each time the overlay opens.
struct GitHubPromptSource: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var owner: String
    var repository: String
    var ref: String
    var path: String
    var category: String?
    var tags: [String]
    var authentication: GitHubSourceAuthentication
    var content: GitHubSourceContent

    init(
        id: String,
        title: String,
        owner: String,
        repository: String,
        ref: String = "main",
        path: String,
        category: String? = nil,
        tags: [String] = [],
        authentication: GitHubSourceAuthentication = .storedToken,
        content: GitHubSourceContent = .wholeFile
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.repository = repository
        self.ref = ref
        self.path = path
        self.category = category
        self.tags = tags
        self.authentication = authentication
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, owner, repository, ref, path, category, tags, authentication, content
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        owner = try values.decode(String.self, forKey: .owner)
        repository = try values.decode(String.self, forKey: .repository)
        ref = try values.decodeIfPresent(String.self, forKey: .ref) ?? "main"
        path = try values.decode(String.self, forKey: .path)
        category = try values.decodeIfPresent(String.self, forKey: .category)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        authentication = try values.decodeIfPresent(GitHubSourceAuthentication.self, forKey: .authentication) ?? .storedToken
        content = try values.decodeIfPresent(GitHubSourceContent.self, forKey: .content) ?? .wholeFile
    }

    var promptID: String { "github-\(id)" }
    var repositoryDisplayName: String { "\(owner)/\(repository)@\(ref)" }

    var hasValidRepositoryPath: Bool {
        let ownerCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let repositoryCharacters = ownerCharacters.union(CharacterSet(charactersIn: "_."))
        return !owner.isEmpty && owner.unicodeScalars.allSatisfy(ownerCharacters.contains)
            && !repository.isEmpty && ![".", ".."].contains(repository)
            && repository.unicodeScalars.allSatisfy(repositoryCharacters.contains)
            && !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ref.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !path.isEmpty && !path.hasPrefix("/")
            && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

/// A local-only prompt assembled from other local or remotely sourced prompts.
struct CompositePromptDefinition: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var componentPromptIDs: [String]
    var separator: String
    var category: String?
    var tags: [String]

    init(
        id: String,
        title: String,
        componentPromptIDs: [String],
        separator: String = "\n\n",
        category: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.componentPromptIDs = componentPromptIDs
        self.separator = separator
        self.category = category
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey { case id, title, componentPromptIDs, separator, category, tags }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        componentPromptIDs = try values.decode([String].self, forKey: .componentPromptIDs)
        separator = try values.decodeIfPresent(String.self, forKey: .separator) ?? "\n\n"
        category = try values.decodeIfPresent(String.self, forKey: .category)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

enum PromptSourceValidationError: Error, Equatable, LocalizedError {
    case invalidSourceID(String)
    case emptySourceTitle(String)
    case incompleteRepository(String)
    case unsupportedFile(String)
    case invalidCompositeID(String)
    case emptyCompositeTitle(String)
    case emptyCompositeComponents(String)
    case duplicatePromptID(String)
    case invalidRepositoryPath(String)
    case unavailableComponent(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidSourceID(let id): "GitHub source id '\(id)' must be a lowercase slug."
        case .emptySourceTitle(let id): "GitHub source '\(id)' needs a title."
        case .incompleteRepository(let id): "GitHub source '\(id)' needs an owner, repository, ref, and file path."
        case .unsupportedFile(let id): "GitHub source '\(id)' must point to a .md, .markdown, or .txt file."
        case .invalidCompositeID(let id): "Composite prompt id '\(id)' must be a lowercase slug."
        case .emptyCompositeTitle(let id): "Composite prompt '\(id)' needs a title."
        case .emptyCompositeComponents(let id): "Composite prompt '\(id)' needs at least one component prompt."
        case .duplicatePromptID(let id): "Prompt id '\(id)' is used by more than one local prompt, GitHub source, or composite."
        case .invalidRepositoryPath(let id): "GitHub source '\(id)' needs a valid owner, repository, ref, and relative file path."
        case .unavailableComponent(let id, let component): "Composite '\(id)' refers to unknown component '\(component)'. Components must be local prompts or GitHub sources."
        }
    }
}

enum CompositePromptResolver {
    static func resolve(
        _ definitions: [CompositePromptDefinition],
        against prompts: [Prompt]
    ) -> (prompts: [Prompt], warnings: [String]) {
        let promptsByID = Dictionary(uniqueKeysWithValues: prompts.map { ($0.id, $0) })
        var resolved: [Prompt] = []
        var warnings: [String] = []

        for definition in definitions {
            let components = definition.componentPromptIDs.compactMap { promptsByID[$0] }
            guard components.count == definition.componentPromptIDs.count else {
                let missing = definition.componentPromptIDs.filter { promptsByID[$0] == nil }
                warnings.append("Composite \"\(definition.title)\" is unavailable because \(missing.joined(separator: ", ")) could not be loaded.")
                continue
            }
            resolved.append(Prompt(
                id: definition.id,
                title: definition.title,
                category: definition.category,
                body: components.map(\.body).joined(separator: definition.separator),
                tags: definition.tags + ["composite"],
                updatedAt: Date()
            ))
        }

        return (resolved, warnings)
    }
}
