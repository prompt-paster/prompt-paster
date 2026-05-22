import AppKit

enum StatusItemIcon {
    static let accessibilityDescription = "Prompt Paster"

    static func makeMenuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        NSColor.black.setFill()

        let promptRect = NSRect(x: 3, y: 4, width: 12, height: 10)
        let promptPath = NSBezierPath(
            roundedRect: promptRect,
            xRadius: 2.2,
            yRadius: 2.2
        )
        promptPath.fill()

        let tailPath = NSBezierPath()
        tailPath.move(to: NSPoint(x: 7.2, y: 4.4))
        tailPath.line(to: NSPoint(x: 5.3, y: 1.9))
        tailPath.line(to: NSPoint(x: 10.4, y: 4.4))
        tailPath.close()
        tailPath.fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        for (index, width) in [6.8, 5.2, 4.0].enumerated() {
            let lineRect = NSRect(
                x: 5.2,
                y: 10.4 - CGFloat(index) * 2.6,
                width: width,
                height: 1.1
            )
            NSBezierPath(roundedRect: lineRect, xRadius: 0.55, yRadius: 0.55).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
