import XCTest
@testable import PromptPaster

final class AgentLibraryTests: XCTestCase {
    func testOlderSourceAndCompositeJSONKeepDefaults() throws {
        let data = Data(#"{"version":1,"prompts":[],"githubSources":[{"id":"rules","title":"Rules","owner":"example","repository":"wiki","path":"rules.md"}],"composites":[{"id":"combined","title":"Combined","componentPromptIDs":["github-rules"]}]}"#.utf8)
        let library = try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: data)
        XCTAssertEqual(library.githubSources.first?.authentication, .storedToken)
        XCTAssertEqual(library.githubSources.first?.content, .wholeFile)
        XCTAssertEqual(library.githubSources.first?.ref, "main")
        XCTAssertEqual(library.composites.first?.separator, "\n\n")
        XCTAssertNoThrow(try library.validated())
    }

    func testExtractsPromptWithoutDocumentationOrFences() throws {
        let document = "# Usage\r\nSome documentation.\r\n\r\n## Paste-Ready Prompt\r\n\r\n```text\r\nYou are an agent.\r\n\r\nKeep this paragraph.\r\n```\r\n\r\n## Maintenance\r\nNot prompt content."
        XCTAssertEqual(try PromptContentExtractor.extract(document, mode: .pasteReadyBlock), "You are an agent.\n\nKeep this paragraph.")
        XCTAssertEqual(try PromptContentExtractor.extract(document, mode: .wholeFile), document)
    }

    func testLongFencePreservesNestedMarkdownAndHeadingInsideBody() throws {
        let document = "## Paste-Ready Prompt\n````markdown\n## Paste-Ready Prompt\n```swift\nlet x = 1\n```\nEnd.\n````\n"
        XCTAssertEqual(try PromptContentExtractor.extract(document, mode: .pasteReadyBlock), "## Paste-Ready Prompt\n```swift\nlet x = 1\n```\nEnd.")
        XCTAssertEqual(try PromptContentExtractor.extract("## Paste-Ready Prompt\n~~~text\nBody\n~~~", mode: .pasteReadyBlock), "Body")
    }

    func testMalformedOrAmbiguousExtractionFailsClosed() {
        for text in ["plain text", "## Paste-Ready Prompt\nprose\n```text\nBody\n```", "## Paste-Ready Prompt\n```text\nBody", "## Paste-Ready Prompt\n```text\n \n```", "## Paste-Ready Prompt\n```python\nprint(1)\n```", "## Paste-Ready Prompt\n```\nOne\n```\n## Paste-Ready Prompt\n```\nTwo\n```"] {
            XCTAssertThrowsError(try PromptContentExtractor.extract(text, mode: .pasteReadyBlock), text)
        }
    }

    func testRejectsTraversalInvalidPathsAndCrossTypeIDs() throws {
        for path in ["../rules.md", "/rules.md", "prompts//rules.md", "prompts/./rules.md", "prompts/../rules.md", "rules.md\n"] {
            XCTAssertFalse(source(path: path).hasValidRepositoryPath)
        }
        XCTAssertTrue(source(path: "docs/my rules #1.md").hasValidRepositoryPath)
        XCTAssertThrowsError(try PromptLibrary(prompts: [Prompt(id: "github-rules", title: "Collision", body: "Body")], githubSources: [source()]).validated())
        XCTAssertThrowsError(try PromptLibrary(prompts: [], githubSources: [source(), source()]).validated())
        XCTAssertThrowsError(try PromptLibrary(prompts: [], composites: [CompositePromptDefinition(id: "combined", title: "Combined", componentPromptIDs: ["missing"])]).validated())
    }

    func testMergePreservesUnmentionedEntriesAndMetadataAndIsIdempotent() throws {
        let old = PromptLibrary(prompts: [Prompt(id: "one", title: "One", category: "Existing", body: "Old", tags: ["keep"]), Prompt(id: "two", title: "Two", body: "Untouched")], githubSources: [source()])
        let patch = Data(#"{"prompts":[{"id":"one","body":"New"}],"githubSources":[{"id":"rules","authentication":"githubCLI","content":"pasteReadyBlock"}]}"#.utf8)
        let updated = try LibraryPatch.merging(patch, into: old)
        XCTAssertEqual(updated.prompts[0].body, "New")
        XCTAssertEqual(updated.prompts[0].category, "Existing")
        XCTAssertEqual(updated.prompts[0].tags, ["keep"])
        XCTAssertEqual(updated.prompts[1], old.prompts[1])
        XCTAssertEqual(updated.githubSources.first?.owner, "example")
        XCTAssertEqual(updated.githubSources.first?.authentication, .githubCLI)
        XCTAssertEqual(try LibraryPatch.merging(patch, into: updated), updated)
    }

    func testDryRunAndInvalidManifestNeverChangeLibraryAndBackupIsExact() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("prompts.json")
        let original = Data("{ \"version\": 1, \"prompts\": [] }\n".utf8)
        try original.write(to: url)
        let patch = Data(#"{"prompts":[{"id":"new","title":"New","body":"Body"}]}"#.utf8)
        let preview = try LibraryPatch.apply(patch, to: url, dryRun: true)
        XCTAssertTrue(preview.changed)
        XCTAssertNil(preview.backupURL)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Backups").path))
        for bad in [#"{"githubSource":[]}"#, #"{"prompts":[{"id":"new","titel":"Typo"}]}"#, #"{"prompts":[{"id":"x","title":"X","body":"B"},{"id":"x","title":"Duplicate","body":"B"}]}"#, #"{"composites":[{"id":"broken","title":"Broken","componentPromptIDs":["missing"]}]}"#] {
            XCTAssertThrowsError(try LibraryPatch.apply(Data(bad.utf8), to: url, dryRun: false))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
        let result = try LibraryPatch.apply(patch, to: url, dryRun: false)
        let backup = try XCTUnwrap(result.backupURL)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
        let repeated = try LibraryPatch.apply(patch, to: url, dryRun: false)
        XCTAssertFalse(repeated.changed)
        XCTAssertNil(repeated.backupURL)
    }

    func testConcurrentAgentMergesPreserveBothWriters() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("prompts.json")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ["one", "two", "three", "four"] {
                group.addTask {
                    let patch = try JSONSerialization.data(withJSONObject: ["prompts": [["id": id, "title": id, "body": id]]])
                    _ = try LibraryPatch.apply(patch, to: url, dryRun: false)
                }
            }
            try await group.waitForAll()
        }
        let saved = try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: Data(contentsOf: url))
        XCTAssertEqual(Set(saved.prompts.map(\.id)), ["one", "two", "three", "four"])
    }

    func testCLIResponseExtractionAndEncodedEndpoint() async throws {
        let body = "## Paste-Ready Prompt\n```text\nActual prompt\n```\nDocs"
        let cli = RecordingCLI(data: try contents(body))
        var configured = source(path: "docs/my rules #1.md")
        configured.ref = "feature/a&b"
        configured.authentication = .githubCLI
        configured.content = .pasteReadyBlock
        let result = await GitHubPromptSourceService(cli: cli).fetchPrompts(for: [configured], token: "never-used")
        XCTAssertEqual(result.errors, [])
        XCTAssertEqual(result.prompts.first?.body, "Actual prompt")
        let endpoint = await cli.endpoint
        XCTAssertTrue(try XCTUnwrap(endpoint).contains("my%20rules%20%231.md?ref=feature/a%26b"))
    }

    func testEmptyAndMalformedRemoteFilesCannotProduceComposite() async throws {
        for body in [" \n", "## Paste-Ready Prompt\nno fence"] {
            var configured = source()
            configured.authentication = .githubCLI
            configured.content = body.contains("##") ? .pasteReadyBlock : .wholeFile
            let result = await GitHubPromptSourceService(cli: RecordingCLI(data: try contents(body))).fetchPrompts(for: [configured], token: nil)
            XCTAssertTrue(result.prompts.isEmpty)
            XCTAssertEqual(result.errors.count, 1)
            XCTAssertTrue(result.errors[0].contains("Rules"))
            let combined = CompositePromptResolver.resolve([CompositePromptDefinition(id: "combined", title: "Combined", componentPromptIDs: ["github-rules"])], against: result.prompts)
            XCTAssertTrue(combined.prompts.isEmpty)
        }
    }

    func testCommandTimeoutAndOutputLimitAreBoundedAndErrorsHideStderr() async throws {
        do {
            _ = try await BoundedCommand.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["3"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        do {
            _ = try await BoundedCommand.run(executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: ["x"], maximumBytes: 1_024)
            XCTFail("Expected output limit")
        } catch { XCTAssertTrue(error.localizedDescription.contains("larger")) }
        do {
            _ = try await BoundedCommand.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo SECRET >&2; exit 1"])
            XCTFail("Expected failure")
        } catch { XCTAssertFalse(error.localizedDescription.contains("SECRET")) }
    }

    func testAnonymousNeverSendsStoredTokenAndHTTPFailuresHideResponseBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceHTTPStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let response = try contents("Public prompt")
        SourceHTTPStub.state.set(status: 200, data: response)
        var configured = source()
        configured.authentication = .anonymous
        let service = GitHubPromptSourceService(session: session)
        let result = await service.fetchPrompts(for: [configured], token: "SENSITIVE")
        XCTAssertEqual(result.prompts.first?.body, "Public prompt")
        XCTAssertNil(SourceHTTPStub.state.request?.value(forHTTPHeaderField: "Authorization"))
        configured.authentication = .storedToken
        _ = await service.fetchPrompts(for: [configured], token: "SENSITIVE")
        XCTAssertEqual(SourceHTTPStub.state.request?.value(forHTTPHeaderField: "Authorization"), "Bearer SENSITIVE")
        SourceHTTPStub.state.set(status: 403, data: Data("SENSITIVE response body".utf8))
        let failed = await service.fetchPrompts(for: [configured], token: "SENSITIVE")
        XCTAssertTrue(failed.prompts.isEmpty)
        XCTAssertTrue(failed.errors.first?.contains("403") == true)
        XCTAssertFalse(failed.errors.joined().contains("SENSITIVE"))
    }

    private func source(path: String = "rules.md") -> GitHubPromptSource {
        GitHubPromptSource(id: "rules", title: "Rules", owner: "example", repository: "wiki", path: path)
    }
    private func contents(_ body: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["encoding": "base64", "content": Data(body.utf8).base64EncodedString()])
    }
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PromptPasterAgentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

private actor RecordingCLI: GitHubCLIReading {
    let data: Data
    var endpoint: String?
    init(data: Data) { self.data = data }
    func read(endpoint: String) async throws -> Data { self.endpoint = endpoint; return data }
}

private final class SourceHTTPStub: URLProtocol, @unchecked Sendable {
    static let state = SourceHTTPState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.state.record(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class SourceHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var data = Data()
    private var storedRequest: URLRequest?
    var request: URLRequest? { lock.withLock { storedRequest } }
    func set(status: Int, data: Data) { lock.withLock { self.status = status; self.data = data } }
    func record(_ request: URLRequest) -> (Int, Data) {
        lock.withLock { storedRequest = request; return (status, data) }
    }
}
