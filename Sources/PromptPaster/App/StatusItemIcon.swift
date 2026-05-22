import AppKit

enum StatusItemIcon {
    static let accessibilityDescription = "Prompt Paster"
    static let title = "Prompt Paster"
    static let symbolName = "text.bubble.fill"
    static let pointSize: CGFloat = 16
    static let titlePointSize: CGFloat = 13
    static let statusItemLength: CGFloat = 108

    static func makeMenuBarImage() -> NSImage {
        let symbolImage = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = symbolImage.withSymbolConfiguration(configuration) ?? symbolImage
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    static func makeMenuBarTitle() -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: titlePointSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }
}
