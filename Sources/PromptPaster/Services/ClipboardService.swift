import AppKit

protocol ClipboardCopying {
    func copyPlainText(_ text: String) throws
}

protocol PasteboardWriting {
    @discardableResult
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: PasteboardWriting {}

struct ClipboardService: ClipboardCopying {
    private let pasteboard: PasteboardWriting

    init(pasteboard: PasteboardWriting = NSPasteboard.general) {
        self.pasteboard = pasteboard
    }

    func copyPlainText(_ text: String) throws {
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardServiceError.writeFailed
        }
    }
}

enum ClipboardServiceError: Error, LocalizedError, Equatable {
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            "Clipboard write failed."
        }
    }
}
