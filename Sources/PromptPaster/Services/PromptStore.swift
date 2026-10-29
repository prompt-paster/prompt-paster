import Foundation

struct PromptStoreReloadResult: Equatable {
    let library: PromptLibrary?
    let validation: PromptLibraryValidation?
    let errorMessage: String?

    var didSucceed: Bool {
        errorMessage == nil
    }
}

struct PromptLibraryFileSignature: Equatable {
    let byteCount: Int
    let contentDigest: UInt64
}

@MainActor
final class PromptStore: ObservableObject {
    static let applicationSupportFolderName = "Prompt Paster"
    static let libraryFileName = "prompts.json"

    @Published private(set) var library: PromptLibrary?
    @Published private(set) var validation: PromptLibraryValidation?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var libraryFileSignature: PromptLibraryFileSignature?
    @Published private(set) var effectivePrompts: [Prompt] = []
    @Published private(set) var isRefreshingSources = false
    @Published private(set) var sourceStatusMessages: [String] = []

    let libraryURL: URL

    private let applicationSupportURL: URL
    private let seedURL: URL?
    private let fileManager: FileManager
    private let githubSourceFetcher: GitHubPromptSourceFetching
    private var remotePrompts: [Prompt] = []
    private var sourceRefreshErrors: [String] = []
    private var sourceRefreshGeneration = 0

    init(
        applicationSupportURL: URL? = nil,
        seedURL: URL? = nil,
        fileManager: FileManager = .default,
        githubSourceFetcher: GitHubPromptSourceFetching = GitHubPromptSourceService()
    ) {
        self.fileManager = fileManager
        self.githubSourceFetcher = githubSourceFetcher
        let baseURL = applicationSupportURL ?? Self.defaultApplicationSupportURL(fileManager: fileManager)
        self.applicationSupportURL = baseURL
        self.libraryURL = baseURL.appendingPathComponent(Self.libraryFileName, isDirectory: false)
        self.seedURL = seedURL ?? Self.bundledSeedURL
    }

    @discardableResult
    func load() -> PromptStoreReloadResult {
        reload()
    }

    @discardableResult
    func reload() -> PromptStoreReloadResult {
        do {
            try ensureLibraryFileExists()
            let data = try Data(contentsOf: libraryURL)
            let decoded = try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: data)
            let loadResult = try decoded.validatedForLoading()
            libraryFileSignature = Self.fileSignature(for: data)
            library = loadResult.library
            validation = loadResult.validation
            remotePrompts = []
            sourceRefreshGeneration += 1
            isRefreshingSources = false
            sourceRefreshErrors = []
            sourceStatusMessages = []
            rebuildEffectivePrompts()
            lastErrorMessage = nil
            return PromptStoreReloadResult(
                library: loadResult.library,
                validation: loadResult.validation,
                errorMessage: nil
            )
        } catch {
            let message = error.localizedDescription
            lastErrorMessage = message
            return PromptStoreReloadResult(library: library, validation: validation, errorMessage: message)
        }
    }

    func prepareLibraryFile() throws -> URL {
        try ensureLibraryFileExists()
        return libraryURL
    }

    @discardableResult
    func save(_ library: PromptLibrary, expectedSignature: PromptLibraryFileSignature? = nil) throws -> PromptLibraryValidation {
        try ensureLibraryFileExists()
        return try LibraryFileAccess.withLock(at: libraryURL) {
            let currentSignature = try currentLibraryFileSignature()
            if let baseline = expectedSignature ?? libraryFileSignature, currentSignature != baseline {
                throw PromptStoreError.libraryChangedOnDisk
            }

            let validation = try library.validated()
            let data = try PromptLibraryCoding.makeEncoder().encode(library)
            try LibraryFileAccess.write(data, to: libraryURL)
            libraryFileSignature = Self.fileSignature(for: data)
            self.library = library
            self.validation = validation
            remotePrompts = []
            sourceRefreshGeneration += 1
            isRefreshingSources = false
            sourceRefreshErrors = []
            sourceStatusMessages = []
            rebuildEffectivePrompts()
            lastErrorMessage = nil
            return validation
        }
    }

    @discardableResult
    func reloadIfChanged() -> Bool {
        guard let signature = try? currentLibraryFileSignature(), signature == libraryFileSignature else {
            return reload().didSucceed
        }
        return false
    }

    func recordError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    func refreshGitHubSources(token: String?) async {
        reloadIfChanged()
        guard let library else { return }
        guard !library.githubSources.isEmpty else {
            remotePrompts = []
            sourceRefreshErrors = []
            rebuildEffectivePrompts()
            return
        }

        isRefreshingSources = true
        sourceRefreshGeneration += 1
        let generation = sourceRefreshGeneration
        let result = await githubSourceFetcher.fetchPrompts(for: library.githubSources, token: token)
        guard generation == sourceRefreshGeneration else { return }
        remotePrompts = result.prompts
        sourceRefreshErrors = result.errors
        rebuildEffectivePrompts()
        isRefreshingSources = false
    }

    private func rebuildEffectivePrompts() {
        guard let library else {
            effectivePrompts = []
            return
        }

        let sourcePromptIDs = Set(library.githubSources.map(\.promptID))
        let availableRemotePrompts = remotePrompts.filter { sourcePromptIDs.contains($0.id) }
        let basePrompts = library.prompts + availableRemotePrompts
        let composites = CompositePromptResolver.resolve(library.composites, against: basePrompts)
        effectivePrompts = basePrompts + composites.prompts
        sourceStatusMessages = sourceRefreshErrors + composites.warnings
    }

    private func ensureLibraryFileExists() throws {
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )

        try LibraryFileAccess.withLock(at: libraryURL) {
            guard !fileManager.fileExists(atPath: libraryURL.path) else {
                return
            }

            guard let seedURL else {
                throw PromptStoreError.seedResourceMissing
            }

            try LibraryFileAccess.write(Data(contentsOf: seedURL), to: libraryURL)
        }
    }

    private func currentLibraryFileSignature() throws -> PromptLibraryFileSignature {
        try Self.fileSignature(for: Data(contentsOf: libraryURL))
    }

    private static func fileSignature(for data: Data) -> PromptLibraryFileSignature {
        var digest: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            digest ^= UInt64(byte)
            digest &*= 1_099_511_628_211
        }
        return PromptLibraryFileSignature(byteCount: data.count, contentDigest: digest)
    }

    static func defaultApplicationSupportURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent(applicationSupportFolderName, isDirectory: true)
    }

    nonisolated static var bundledSeedURL: URL? {
        Bundle.main.url(forResource: "SeedPrompts", withExtension: "json")
            ?? Bundle.module.url(forResource: "SeedPrompts", withExtension: "json")
    }
}

enum PromptStoreError: Error, LocalizedError {
    case seedResourceMissing
    case libraryChangedOnDisk

    var errorDescription: String? {
        switch self {
        case .seedResourceMissing:
            "Bundled SeedPrompts.json could not be found."
        case .libraryChangedOnDisk:
            "prompts.json changed outside the editor. Reload the library before saving."
        }
    }
}
