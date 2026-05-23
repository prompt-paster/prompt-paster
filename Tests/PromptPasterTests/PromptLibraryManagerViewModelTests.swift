import Combine
import XCTest
@testable import PromptPaster

@MainActor
final class PromptLibraryManagerViewModelTests: XCTestCase {
    private var temporaryURLs: [URL] = []
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() async throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        cancellables.removeAll()
        try await super.tearDown()
    }

    func testDirtyDraftBlocksSelectionChangesUntilDiscarded() throws {
        let store = try makeLoadedStore(prompts: [
            Prompt(id: "one", title: "One", body: "One body"),
            Prompt(id: "two", title: "Two", body: "Two body")
        ])
        let viewModel = PromptLibraryManagerViewModel(promptStore: store)

        var draft = try XCTUnwrap(viewModel.draft)
        draft.title = "Unsaved"
        viewModel.updateDraft(draft)
        viewModel.requestSelection("two")

        XCTAssertEqual(viewModel.selectedPromptID, "one")
        XCTAssertEqual(viewModel.errorMessage, "Save or discard changes before switching prompts.")

        viewModel.discardChanges()
        viewModel.requestSelection("two")

        XCTAssertEqual(viewModel.selectedPromptID, "two")
        XCTAssertEqual(viewModel.draft?.title, "Two")
    }

    func testDirtyDraftBlocksReloadUntilDiscarded() throws {
        let store = try makeLoadedStore(prompts: [
            Prompt(id: "one", title: "One", body: "One body")
        ])
        let viewModel = PromptLibraryManagerViewModel(promptStore: store)

        var draft = try XCTUnwrap(viewModel.draft)
        draft.body = "Unsaved body"
        viewModel.updateDraft(draft)
        viewModel.reloadLibrary()

        XCTAssertEqual(viewModel.draft?.body, "Unsaved body")
        XCTAssertEqual(viewModel.errorMessage, "Save or discard changes before reloading.")
    }

    func testInvalidDraftShowsFieldErrorsAndDisablesSave() throws {
        let store = try makeLoadedStore(prompts: [
            Prompt(id: "one", title: "One", body: "One body")
        ])
        let viewModel = PromptLibraryManagerViewModel(promptStore: store)

        var draft = try XCTUnwrap(viewModel.draft)
        draft.title = " "
        draft.body = ""
        viewModel.updateDraft(draft)

        XCTAssertEqual(viewModel.titleErrorMessage, "Title is required.")
        XCTAssertEqual(viewModel.bodyErrorMessage, "Body is required.")
        XCTAssertTrue(viewModel.saveDisabled)
    }

    func testStoreChangesNotifyManagerViewModelObservers() throws {
        let store = try makeLoadedStore(prompts: [
            Prompt(id: "one", title: "One", body: "One body")
        ])
        let viewModel = PromptLibraryManagerViewModel(promptStore: store)
        let expectation = expectation(description: "view model forwards prompt store changes")
        expectation.assertForOverFulfill = false

        viewModel.objectWillChange
            .sink {
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try store.save(PromptLibrary(prompts: [
            Prompt(id: "one", title: "Changed", body: "Changed body")
        ]))

        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(viewModel.prompts.map(\.title), ["Changed"])
    }

    private func makeLoadedStore(prompts: [Prompt]) throws -> PromptStore {
        let rootURL = makeTemporaryDirectory()
        let seedURL = rootURL.appendingPathComponent("SeedPrompts.json")
        let appSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        try writeLibrary(PromptLibrary(prompts: prompts), to: seedURL)
        let store = PromptStore(applicationSupportURL: appSupportURL, seedURL: seedURL)
        XCTAssertTrue(store.load().didSucceed)
        return store
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
