import AppKit
import XCTest
@testable import PromptPaster

final class StatusItemIconTests: XCTestCase {
    func testMenuBarImageUsesTemplateRenderingMetadata() {
        let image = StatusItemIcon.makeMenuBarImage()

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(StatusItemIcon.symbolName, "text.bubble.fill")
        XCTAssertEqual(StatusItemIcon.pointSize, 16)
        XCTAssertEqual(image.accessibilityDescription, "Prompt Paster")
    }

    func testMenuBarTitleProvidesTextFallback() {
        let title = StatusItemIcon.makeMenuBarTitle()

        XCTAssertEqual(title.string, "Prompt Paster")
        XCTAssertEqual(StatusItemIcon.titlePointSize, 13)
        XCTAssertEqual(StatusItemIcon.statusItemLength, 108)
        XCTAssertNotNil(title.attribute(.font, at: 0, effectiveRange: nil))
        XCTAssertNotNil(title.attribute(.foregroundColor, at: 0, effectiveRange: nil))
    }

    func testMenuBarImageRendersUsefulOpaqueMask() throws {
        let image = StatusItemIcon.makeMenuBarImage()
        let bitmap = try renderTemplateMask(image)

        let visiblePixels = countVisiblePixels(in: bitmap)
        let totalPixels = bitmap.pixelsWide * bitmap.pixelsHigh
        let coverage = Double(visiblePixels) / Double(totalPixels)

        XCTAssertGreaterThan(
            coverage,
            0.08,
            "Menu-bar icon mask should have enough filled area to stay discoverable."
        )
        XCTAssertLessThan(
            coverage,
            0.55,
            "Menu-bar icon mask should stay glyph-like rather than filling the whole status item."
        )
    }

    private func renderTemplateMask(_ image: NSImage) throws -> NSBitmapImageRep {
        let size = 36
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: size,
                pixelsHigh: size,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        image.draw(
            in: NSRect(x: 3, y: 3, width: 30, height: 30),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        return bitmap
    }

    private func countVisiblePixels(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0

        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.12 else {
                    continue
                }
                count += 1
            }
        }

        return count
    }
}
