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

    let libraryURL: URL

    private let applicationSupportURL: URL
    private let seedURL: URL?
    private let fileManager: FileManager

    init(
        applicationSupportURL: URL? = nil,
        seedURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
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
            library = loadResult.library
            validation = loadResult.validation
            libraryFileSignature = Self.fileSignature(for: data)
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
    func save(_ library: PromptLibrary) throws -> PromptLibraryValidation {
        try ensureLibraryFileExists()
        let currentSignature = try currentLibraryFileSignature()
        if let libraryFileSignature, currentSignature != libraryFileSignature {
            throw PromptStoreError.libraryChangedOnDisk
        }

        let validation = try library.validated()
        let data = try PromptLibraryCoding.makeEncoder().encode(library)
        try data.write(to: libraryURL, options: .atomic)
        self.library = library
        self.validation = validation
        libraryFileSignature = Self.fileSignature(for: data)
        lastErrorMessage = nil
        return validation
    }

    func recordError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    private func ensureLibraryFileExists() throws {
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )

        guard !fileManager.fileExists(atPath: libraryURL.path) else {
            return
        }

        guard let seedURL else {
            throw PromptStoreError.seedResourceMissing
        }

        try fileManager.copyItem(at: seedURL, to: libraryURL)
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
        Bundle.module.url(forResource: "SeedPrompts", withExtension: "json")
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
