import AppKit
import XCTest
@testable import PromptPaster

final class ClipboardServiceTests: XCTestCase {
    @MainActor
    func testCopyPlainTextClearsAndWritesStringPasteboardType() throws {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)

        try service.copyPlainText("Prompt body")

        XCTAssertEqual(pasteboard.clearCallCount, 1)
        XCTAssertEqual(pasteboard.writtenStrings, ["Prompt body"])
        XCTAssertEqual(pasteboard.writtenTypes, [.string])
    }

    @MainActor
    func testCopyPlainTextThrowsWhenPasteboardWriteFails() {
        let pasteboard = FakePasteboard(writeResult: false)
        let service = ClipboardService(pasteboard: pasteboard)

        XCTAssertThrowsError(try service.copyPlainText("Prompt body")) { error in
            XCTAssertEqual(error as? ClipboardServiceError, .writeFailed)
        }

        XCTAssertEqual(pasteboard.clearCallCount, 2)
        XCTAssertEqual(pasteboard.writtenStrings, ["Prompt body"])
    }

    @MainActor
    func testCopyPlainTextRestoresPreviousPasteboardItemsWhenWriteFails() {
        let previousItem = NSPasteboardItem()
        previousItem.setString("Previous body", forType: .string)
        let pasteboard = FakePasteboard(items: [previousItem], writeResult: false)
        let service = ClipboardService(pasteboard: pasteboard)

        XCTAssertThrowsError(try service.copyPlainText("Prompt body")) { error in
            XCTAssertEqual(error as? ClipboardServiceError, .writeFailed)
        }

        XCTAssertEqual(pasteboard.currentString, "Previous body")
        XCTAssertEqual(pasteboard.restoreCallCount, 1)
    }

    @MainActor
    func testCopyPlainTextReportsRestoreFailureWhenPreviousItemsCannotBeRestored() {
        let previousItem = NSPasteboardItem()
        previousItem.setString("Previous body", forType: .string)
        let pasteboard = FakePasteboard(
            items: [previousItem],
            writeResult: false,
            restoreResult: false
        )
        let service = ClipboardService(pasteboard: pasteboard)

        XCTAssertThrowsError(try service.copyPlainText("Prompt body")) { error in
            XCTAssertEqual(error as? ClipboardServiceError, .writeFailedAndRestoreFailed)
        }
    }
}

@MainActor
private final class FakePasteboard: PasteboardAccessing {
    var clearCallCount = 0
    var restoreCallCount = 0
    var writtenStrings: [String] = []
    var writtenTypes: [NSPasteboard.PasteboardType] = []

    private(set) var items: [NSPasteboardItem]

    private let writeResult: Bool
    private let restoreResult: Bool

    init(
        items: [NSPasteboardItem] = [],
        writeResult: Bool = true,
        restoreResult: Bool = true
    ) {
        self.items = items
        self.writeResult = writeResult
        self.restoreResult = restoreResult
    }

    var pasteboardItems: [NSPasteboardItem]? {
        items
    }

    var currentString: String? {
        items.first?.string(forType: .string)
    }

    func clearContents() -> Int {
        clearCallCount += 1
        items = []
        return clearCallCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        writtenStrings.append(string)
        writtenTypes.append(dataType)

        guard writeResult else {
            return false
        }

        let item = NSPasteboardItem()
        item.setString(string, forType: dataType)
        items = [item]
        return writeResult
    }

    func writeObjects(_ objects: [NSPasteboardItem]) -> Bool {
        restoreCallCount += 1

        guard restoreResult else {
            return false
        }

        items = objects
        return true
    }
}
