import AppKit
import XCTest
@testable import PromptPaster

@MainActor
final class MainMenuBuilderTests: XCTestCase {
    func testMainMenuIncludesSelectAllForFocusedTextFields() {
        let target = MenuTarget()
        let menu = MainMenuBuilder.build(quitTarget: target, quitAction: #selector(MenuTarget.quit))
        let editMenu = menu.items.compactMap(\.submenu).first { $0.title == "Edit" }

        let selectAllItem = editMenu?.items.first { $0.action == #selector(NSText.selectAll(_:)) }

        XCTAssertNotNil(selectAllItem)
        XCTAssertEqual(selectAllItem?.keyEquivalent, "a")
        XCTAssertNil(selectAllItem?.target)
    }

    func testMainMenuKeepsQuitCommandRoutedToAppDelegateTarget() {
        let target = MenuTarget()
        let menu = MainMenuBuilder.build(quitTarget: target, quitAction: #selector(MenuTarget.quit))
        let appMenu = menu.items.compactMap(\.submenu).first { $0.title == "Prompt Paster" }

        let quitItem = appMenu?.items.first { $0.action == #selector(MenuTarget.quit) }

        XCTAssertNotNil(quitItem)
        XCTAssertEqual(quitItem?.keyEquivalent, "q")
        XCTAssertTrue(quitItem?.target === target)
    }

    private final class MenuTarget: NSObject {
        @objc func quit() {}
    }
}
