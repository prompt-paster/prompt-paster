import XCTest
@testable import PromptPaster

@MainActor
final class PromptSourcesAndHomeTests: XCTestCase {
    func testCompositeResolverPreservesConfiguredComponentOrder() {
        let resolved = CompositePromptResolver.resolve([
            CompositePromptDefinition(
                id: "combined",
                title: "Combined",
                componentPromptIDs: ["second", "first"],
                separator: "\n---\n"
            )
        ], against: [
            Prompt(id: "first", title: "First", body: "First body"),
            Prompt(id: "second", title: "Second", body: "Second body")
        ])

        XCTAssertEqual(resolved.prompts.map(\.id), ["combined"])
        XCTAssertEqual(resolved.prompts.first?.body, "Second body\n---\nFirst body")
        XCTAssertEqual(resolved.warnings, [])
    }

    func testCompositeResolverOmitsIncompleteCompositeInsteadOfCopyingPartialPrompt() {
        let resolved = CompositePromptResolver.resolve([
            CompositePromptDefinition(
                id: "combined",
                title: "Combined",
                componentPromptIDs: ["first", "missing"]
            )
        ], against: [Prompt(id: "first", title: "First", body: "First body")])

        XCTAssertEqual(resolved.prompts, [])
        XCTAssertEqual(resolved.warnings.count, 1)
        XCTAssertTrue(resolved.warnings[0].contains("missing"))
    }

    func testStoreIncludesFetchedGitHubPromptsAndResolvedComposites() async throws {
        let rootURL = try makeTemporaryDirectory()
        let seedURL = rootURL.appendingPathComponent("SeedPrompts.json")
        let source = GitHubPromptSource(
            id: "team-rules",
            title: "Team rules",
            owner: "example",
            repository: "rules",
            path: "prompts/rules.md"
        )
        let library = PromptLibrary(
            prompts: [Prompt(id: "local", title: "Local", body: "Local body")],
            githubSources: [source],
            composites: [CompositePromptDefinition(
                id: "combined",
                title: "Combined",
                componentPromptIDs: ["local", "github-team-rules"]
            )]
        )
        try writeLibrary(library, to: seedURL)
        let fetcher = FakeGitHubSourceFetcher(prompts: [
            Prompt(id: "github-team-rules", title: "Team rules", body: "Remote body")
        ])
        let store = PromptStore(
            applicationSupportURL: rootURL.appendingPathComponent("Application Support"),
            seedURL: seedURL,
            githubSourceFetcher: fetcher
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        XCTAssertTrue(store.load().didSucceed)
        await store.refreshGitHubSources(token: "secret-not-persisted")

        XCTAssertEqual(store.effectivePrompts.map(\.id), ["local", "github-team-rules", "combined"])
        XCTAssertEqual(store.effectivePrompts.last?.body, "Local body\n\nRemote body")
        XCTAssertEqual(fetcher.tokens, ["secret-not-persisted"])
    }

    func testHomeSlotsNormalizeAndPersistCustomOrderAndKeys() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults, loginItemManager: HomeTestLoginItemManager())

        XCTAssertTrue(store.homeScreenEnabled)
        store.toggleFavorite(promptID: "first")
        store.toggleFavorite(promptID: "second")
        store.setHomePromptKey("z", for: "second")
        store.moveHomePrompt("second", before: "first")

        XCTAssertEqual(store.homePromptSlots, [
            PromptHomeSlot(promptID: "second", key: "z"),
            PromptHomeSlot(promptID: "first", key: "a")
        ])

        let reloaded = SettingsStore(defaults: defaults, loginItemManager: HomeTestLoginItemManager())
        XCTAssertEqual(reloaded.homePromptSlots, store.homePromptSlots)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptPasterSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeLibrary(_ library: PromptLibrary, to url: URL) throws {
        let data = try PromptLibraryCoding.makeEncoder().encode(library)
        try data.write(to: url)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PromptPasterSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FakeGitHubSourceFetcher: GitHubPromptSourceFetching, @unchecked Sendable {
    let prompts: [Prompt]
    private(set) var tokens: [String?] = []

    init(prompts: [Prompt]) {
        self.prompts = prompts
    }

    func fetchPrompts(
        for sources: [GitHubPromptSource],
        token: String?
    ) async -> (prompts: [Prompt], errors: [String]) {
        tokens.append(token)
        return (prompts, [])
    }
}

private struct HomeTestLoginItemManager: LoginItemManaging {
    let launchAtLoginStatus: LaunchAtLoginStatus = .disabled
    func setLaunchAtLoginEnabled(_: Bool) throws {}
    func openLoginItemsSettings() {}
}
