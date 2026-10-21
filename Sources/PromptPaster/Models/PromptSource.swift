import Foundation

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

    init(
        id: String,
        title: String,
        owner: String,
        repository: String,
        ref: String = "main",
        path: String,
        category: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.repository = repository
        self.ref = ref
        self.path = path
        self.category = category
        self.tags = tags
    }

    var promptID: String { "github-\(id)" }
    var repositoryDisplayName: String { "\(owner)/\(repository)@\(ref)" }
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
}

enum PromptSourceValidationError: Error, Equatable, LocalizedError {
    case invalidSourceID(String)
    case emptySourceTitle(String)
    case incompleteRepository(String)
    case unsupportedFile(String)
    case invalidCompositeID(String)
    case emptyCompositeTitle(String)
    case emptyCompositeComponents(String)

    var errorDescription: String? {
        switch self {
        case .invalidSourceID(let id): "GitHub source id '\(id)' must be a lowercase slug."
        case .emptySourceTitle(let id): "GitHub source '\(id)' needs a title."
        case .incompleteRepository(let id): "GitHub source '\(id)' needs an owner, repository, ref, and file path."
        case .unsupportedFile(let id): "GitHub source '\(id)' must point to a .md, .markdown, or .txt file."
        case .invalidCompositeID(let id): "Composite prompt id '\(id)' must be a lowercase slug."
        case .emptyCompositeTitle(let id): "Composite prompt '\(id)' needs a title."
        case .emptyCompositeComponents(let id): "Composite prompt '\(id)' needs at least one component prompt."
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
