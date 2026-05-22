import AppKit
import XCTest
@testable import PromptPaster

final class StatusItemIconTests: XCTestCase {
    func testMenuBarImageUsesTemplateRenderingMetadata() {
        let image = StatusItemIcon.makeMenuBarImage()

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(image.accessibilityDescription, "Prompt Paster")
    }
}
