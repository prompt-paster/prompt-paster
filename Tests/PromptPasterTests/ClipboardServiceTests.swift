import AppKit
import XCTest
@testable import PromptPaster

final class ClipboardServiceTests: XCTestCase {
    func testCopyPlainTextClearsAndWritesStringPasteboardType() throws {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)

        try service.copyPlainText("Prompt body")

        XCTAssertEqual(pasteboard.clearCallCount, 1)
        XCTAssertEqual(pasteboard.writtenString, "Prompt body")
        XCTAssertEqual(pasteboard.writtenType, .string)
    }

    func testCopyPlainTextThrowsWhenPasteboardWriteFails() {
        let pasteboard = FakePasteboard(writeResult: false)
        let service = ClipboardService(pasteboard: pasteboard)

        XCTAssertThrowsError(try service.copyPlainText("Prompt body")) { error in
            XCTAssertEqual(error as? ClipboardServiceError, .writeFailed)
        }

        XCTAssertEqual(pasteboard.clearCallCount, 1)
        XCTAssertEqual(pasteboard.writtenString, "Prompt body")
        XCTAssertEqual(pasteboard.writtenType, .string)
    }
}

private final class FakePasteboard: PasteboardWriting {
    var clearCallCount = 0
    var writtenString: String?
    var writtenType: NSPasteboard.PasteboardType?

    private let writeResult: Bool

    init(writeResult: Bool = true) {
        self.writeResult = writeResult
    }

    func clearContents() -> Int {
        clearCallCount += 1
        return clearCallCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        writtenString = string
        writtenType = dataType
        return writeResult
    }
}
