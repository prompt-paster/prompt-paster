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

    func testRefreshAutomaticallyReloadsAgentEditsAndKeepsUnavailableFavoriteIDs() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = root.appendingPathComponent("seed.json")
        try writeLibrary(PromptLibrary(prompts: [Prompt(id: "local", title: "Local", body: "Old")]), to: seed)
        let store = PromptStore(applicationSupportURL: root.appendingPathComponent("Support"), seedURL: seed,
                                githubSourceFetcher: FakeGitHubSourceFetcher(prompts: []))
        XCTAssertTrue(store.load().didSucceed)
        let patch = Data(#"{"prompts":[{"id":"local","body":"Agent update"}],"githubSources":[{"id":"remote","title":"Remote","owner":"example","repository":"wiki","path":"rules.md"}],"composites":[{"id":"combined","title":"Combined","componentPromptIDs":["local","github-remote"]}]}"#.utf8)
        _ = try LibraryPatch.apply(patch, to: store.libraryURL, dryRun: false)
        await store.refreshGitHubSources(token: nil)
        XCTAssertEqual(store.effectivePrompts.first?.body, "Agent update")
        XCTAssertEqual(store.effectivePrompts.map(\.id), ["local"])
        let settings = SettingsStore(defaults: makeDefaults(), loginItemManager: HomeTestLoginItemManager())
        settings.toggleFavorite(promptID: "combined")
        settings.pruneHomePrompts(keepingPromptIDs: store.library?.configuredPromptIDs ?? [])
        XCTAssertTrue(settings.isFavorite(promptID: "combined"))
    }

    func testLateSourceRefreshCannotReplaceNewerConfiguration() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let seed = root.appendingPathComponent("seed.json")
        let source = GitHubPromptSource(id: "remote", title: "Remote", owner: "example", repository: "wiki", path: "rules.md")
        try writeLibrary(PromptLibrary(prompts: [], githubSources: [source]), to: seed)
        let fetcher = SuspendedSourceFetcher()
        let store = PromptStore(applicationSupportURL: root.appendingPathComponent("Support"), seedURL: seed, githubSourceFetcher: fetcher)
        XCTAssertTrue(store.load().didSucceed)
        let first = Task { await store.refreshGitHubSources(token: nil) }
        while !(await fetcher.started) { await Task.yield() }
        try store.save(PromptLibrary(prompts: [Prompt(id: "local", title: "Local", body: "New library")]))
        await fetcher.finish()
        await first.value
        XCTAssertEqual(store.effectivePrompts.map(\.id), ["local"])
        XCTAssertFalse(store.isRefreshingSources)
    }

    func testInstalledCLIPreferencesUseTheExistingAppDomainWithoutAddingOwnSuite() throws {
        let installed = try LibraryCommandLine.appDefaults(bundleIdentifier: "com.shaypal5.prompt-paster")
        XCTAssertTrue(installed === UserDefaults.standard)
        // The unbundled SwiftPM binary must still be able to address the app's domain.
        let development = try LibraryCommandLine.appDefaults(bundleIdentifier: nil)
        XCTAssertFalse(development === UserDefaults.standard)
    }

    func testAddingNinthFavoritePreservesLegacyOrderAndPersistsAllSixteenUniqueKeys() throws {
        let suite = "PromptPasterCapacity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let oldKeys = ["a", "d", "f", "g", "j", "k", "s", "h"]
        let oldSlots = oldKeys.enumerated().map { PromptHomeSlot(promptID: "legacy-\($0.offset)", key: $0.element) }
        defaults.set(try JSONEncoder().encode(oldSlots), forKey: "settings.homePromptSlots")
        let store = SettingsStore(defaults: defaults, loginItemManager: HomeTestLoginItemManager())
        XCTAssertEqual(store.homePromptSlots, oldSlots)
        store.toggleFavorite(promptID: "base-only")
        XCTAssertEqual(Array(store.homePromptSlots.prefix(8)), oldSlots)
        XCTAssertEqual(store.homePromptSlots.last, PromptHomeSlot(promptID: "base-only", key: "l"))
        for index in 10...16 { store.toggleFavorite(promptID: "new-\(index)") }
        XCTAssertEqual(store.homePromptSlots.count, 16)
        XCTAssertEqual(Set(store.homePromptSlots.map(\.key)).count, 16)
        let fullSlots = store.homePromptSlots
        store.toggleFavorite(promptID: "overflow")
        XCTAssertEqual(store.homePromptSlots, fullSlots)
        let reloaded = SettingsStore(defaults: defaults, loginItemManager: HomeTestLoginItemManager())
        XCTAssertEqual(reloaded.homePromptSlots, fullSlots)
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

private actor SuspendedSourceFetcher: GitHubPromptSourceFetching {
    var started = false
    var continuation: CheckedContinuation<Void, Never>?
    func fetchPrompts(for sources: [GitHubPromptSource], token: String?) async -> (prompts: [Prompt], errors: [String]) {
        await withCheckedContinuation { continuation in self.continuation = continuation; started = true }
        return ([Prompt(id: "github-remote", title: "Remote", body: "Stale")], [])
    }
    func finish() { continuation?.resume(); continuation = nil }
}
