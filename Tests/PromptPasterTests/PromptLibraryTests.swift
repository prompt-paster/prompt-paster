import XCTest
@testable import PromptPaster

final class PromptLibraryTests: XCTestCase {
    func testDecodesValidLibrary() throws {
        let data = """
        {
          "version": 1,
          "prompts": [
            {
              "id": "wait-ci-ready-merge",
              "title": "Wait CI + Merge Check",
              "category": "PR",
              "body": "Wait until CI completes.",
              "shortcut": "1",
              "tags": ["ci", "merge"],
              "updatedAt": "2026-05-21T00:00:00Z",
              "unknownFutureField": true
            }
          ],
          "unknownLibraryField": "tolerated"
        }
        """.data(using: .utf8)!

        let library = try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: data)
        let validation = try library.validated()

        XCTAssertEqual(library.version, 1)
        XCTAssertEqual(library.prompts.count, 1)
        XCTAssertEqual(library.prompts[0].id, "wait-ci-ready-merge")
        XCTAssertEqual(library.prompts[0].tags, ["ci", "merge"])
        XCTAssertEqual(validation.warnings, [])
    }

    func testValidationRejectsMissingRequiredFields() {
        XCTAssertThrowsError(try PromptLibrary(prompts: [
            Prompt(id: " ", title: "Title", body: "Body")
        ]).validated()) { error in
            XCTAssertEqual(error as? PromptLibraryValidationError, .missingID(index: 0))
        }

        XCTAssertThrowsError(try PromptLibrary(prompts: [
            Prompt(id: "sample", title: " ", body: "Body")
        ]).validated()) { error in
            XCTAssertEqual(error as? PromptLibraryValidationError, .missingTitle(id: "sample"))
        }

        XCTAssertThrowsError(try PromptLibrary(prompts: [
            Prompt(id: "sample", title: "Title", body: " ")
        ]).validated()) { error in
            XCTAssertEqual(error as? PromptLibraryValidationError, .missingBody(id: "sample"))
        }
    }

    func testValidationRejectsWhitespacePaddedAndInvalidIDs() {
        XCTAssertThrowsError(try PromptLibrary(prompts: [
            Prompt(id: " sample", title: "Title", body: "Body")
        ]).validated()) { error in
            XCTAssertEqual(error as? PromptLibraryValidationError, .invalidID(" sample"))
        }

        XCTAssertThrowsError(try PromptLibrary(prompts: [
            Prompt(id: "Not A Slug", title: "Title", body: "Body")
        ]).validated()) { error in
            XCTAssertEqual(error as? PromptLibraryValidationError, .invalidID("Not A Slug"))
        }
    }

    func testValidationWarnsOnDuplicateIDsAndKeepsFirstPromptLoadable() throws {
        let library = PromptLibrary(prompts: [
            Prompt(id: "duplicate", title: "First", body: "Body"),
            Prompt(id: "duplicate", title: "Second", body: "Body")
        ])

        let result = try library.validatedForLoading()

        XCTAssertEqual(result.library.prompts.map(\.title), ["First"])
        XCTAssertEqual(result.validation.warnings, [
            .duplicateID(id: "duplicate", skippedIndexes: [1])
        ])
    }

    func testValidationWarnsOnShortcutConflicts() throws {
        let library = PromptLibrary(prompts: [
            Prompt(id: "first", title: "First", body: "Body", shortcut: "a"),
            Prompt(id: "second", title: "Second", body: "Body", shortcut: "A")
        ])

        let validation = try library.validated()

        XCTAssertEqual(validation.warnings, [
            .shortcutConflict(shortcut: "A", promptIDs: ["first", "second"])
        ])
    }

    func testBundledSeedLibraryDecodesAndValidates() throws {
        let seedURL = try XCTUnwrap(PromptStore.bundledSeedURL)
        let data = try Data(contentsOf: seedURL)

        let library = try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: data)
        let validation = try library.validated()

        XCTAssertEqual(library.version, 1)
        XCTAssertGreaterThanOrEqual(library.prompts.count, 20)
        XCTAssertLessThanOrEqual(library.prompts.count, 35)
        XCTAssertEqual(validation.warnings, [])
    }
}
