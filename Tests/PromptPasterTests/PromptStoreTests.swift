import XCTest
@testable import PromptPaster

@MainActor
final class PromptStoreTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() async throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        try await super.tearDown()
    }

    func testFirstRunCopiesSeedLibrary() throws {
        let rootURL = makeTemporaryDirectory()
        let seedURL = rootURL.appendingPathComponent("SeedPrompts.json")
        let appSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        try writeLibrary(.init(prompts: [
            Prompt(id: "seed", title: "Seed", body: "Seed body")
        ]), to: seedURL)

        let store = PromptStore(applicationSupportURL: appSupportURL, seedURL: seedURL)
        let result = store.load()

        XCTAssertTrue(result.didSucceed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.libraryURL.path))
        XCTAssertEqual(store.library?.prompts.map(\.id), ["seed"])
    }

    func testInvalidJSONKeepsLastValidLibraryInMemory() throws {
        let rootURL = makeTemporaryDirectory()
        let seedURL = rootURL.appendingPathComponent("SeedPrompts.json")
        let appSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        try writeLibrary(.init(prompts: [
            Prompt(id: "seed", title: "Seed", body: "Seed body")
        ]), to: seedURL)

        let store = PromptStore(applicationSupportURL: appSupportURL, seedURL: seedURL)
        XCTAssertTrue(store.load().didSucceed)
        XCTAssertEqual(store.library?.prompts.map(\.id), ["seed"])

        try "{ invalid json".write(to: store.libraryURL, atomically: true, encoding: .utf8)
        let result = store.reload()

        XCTAssertFalse(result.didSucceed)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(store.library?.prompts.map(\.id), ["seed"])
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptPasterTests-\(UUID().uuidString)", isDirectory: true)
        temporaryURLs.append(url)
        return url
    }

    private func writeLibrary(_ library: PromptLibrary, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PromptLibraryCoding.makeEncoder().encode(library)
        try data.write(to: url)
    }
}
