import AppKit

@MainActor
protocol ClipboardCopying {
    func copyPlainText(_ text: String) throws
}

@MainActor
protocol PasteboardAccessing {
    var pasteboardItems: [NSPasteboardItem]? { get }

    @discardableResult
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    func writeObjects(_ objects: [NSPasteboardItem]) -> Bool
}

struct SystemPasteboard: PasteboardAccessing {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var pasteboardItems: [NSPasteboardItem]? {
        pasteboard.pasteboardItems
    }

    @discardableResult
    func clearContents() -> Int {
        pasteboard.clearContents()
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        pasteboard.setString(string, forType: dataType)
    }

    func writeObjects(_ objects: [NSPasteboardItem]) -> Bool {
        pasteboard.writeObjects(objects)
    }
}

struct ClipboardService: ClipboardCopying {
    private let pasteboard: PasteboardAccessing

    init(pasteboard: PasteboardAccessing = SystemPasteboard()) {
        self.pasteboard = pasteboard
    }

    func copyPlainText(_ text: String) throws {
        let previousItems = pasteboard.pasteboardItems?.map(Self.snapshot) ?? []

        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            guard restore(previousItems) else {
                throw ClipboardServiceError.writeFailedAndRestoreFailed
            }
            throw ClipboardServiceError.writeFailed
        }
    }

    private func restore(_ items: [NSPasteboardItem]) -> Bool {
        pasteboard.clearContents()

        guard !items.isEmpty else {
            return true
        }

        return pasteboard.writeObjects(items)
    }

    private static func snapshot(_ item: NSPasteboardItem) -> NSPasteboardItem {
        let snapshot = NSPasteboardItem()

        for type in item.types {
            if let data = item.data(forType: type) {
                snapshot.setData(data, forType: type)
            }
        }

        return snapshot
    }
}

enum ClipboardServiceError: Error, LocalizedError, Equatable {
    case writeFailed
    case writeFailedAndRestoreFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            "Clipboard write failed."
        case .writeFailedAndRestoreFailed:
            "Clipboard write failed and previous clipboard contents could not be restored."
        }
    }
}
