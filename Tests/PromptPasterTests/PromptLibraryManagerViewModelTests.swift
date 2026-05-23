import Combine
import XCTest
@testable import PromptPaster

@MainActor
final class PromptLibraryManagerViewModelTests: XCTestCase {
    nonisolated(unsafe) private var temporaryURLs: [URL] = []
    nonisolated(unsafe) private var cancellables: Set<AnyCancellable> = []

    override func tearDownWithError() throws {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        cancellables.removeAll()
        try super.tearDownWithError()
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

    func testExternalStoreChangeRefreshesCleanDraft() throws {
        let store = try makeLoadedStore(prompts: [
            Prompt(id: "one", title: "One", body: "One body")
        ])
        let viewModel = PromptLibraryManagerViewModel(promptStore: store)

        try store.save(PromptLibrary(prompts: [
            Prompt(id: "one", title: "Changed", body: "Changed body")
        ]))

        XCTAssertEqual(viewModel.selectedPromptID, "one")
        XCTAssertEqual(viewModel.draft?.title, "Changed")
        XCTAssertEqual(viewModel.draft?.body, "Changed body")
        XCTAssertFalse(viewModel.isDirty)
    }

    func testExternalStoreChangeDoesNotDiscardDirtyDraft() throws {
        let store = try makeLoadedStore(prompts: [
            Prompt(id: "one", title: "One", body: "One body")
        ])
        let viewModel = PromptLibraryManagerViewModel(promptStore: store)

        var draft = try XCTUnwrap(viewModel.draft)
        draft.title = "Unsaved"
        viewModel.updateDraft(draft)

        try store.save(PromptLibrary(prompts: [
            Prompt(id: "one", title: "External", body: "External body")
        ]))

        XCTAssertEqual(viewModel.draft?.title, "Unsaved")
        XCTAssertTrue(viewModel.isDirty)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Prompt library changed while this editor has unsaved changes. Save or discard changes before continuing."
        )
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
