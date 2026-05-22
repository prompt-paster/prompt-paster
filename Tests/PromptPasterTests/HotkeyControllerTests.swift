import Carbon.HIToolbox
import XCTest
@testable import PromptPaster

@MainActor
final class HotkeyControllerTests: XCTestCase {
    func testDefaultFallbackShortcutIsControlOptionSpace() {
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.displayName, "Control + Option + Space")
    }

    func testTriggerRouterForwardsHotkeyTriggerToHandler() {
        let handler = FakeHotkeyHandler()
        let router = HotkeyTriggerRouter(handler: handler)

        router.handleTrigger()
        router.handleTrigger()

        XCTAssertEqual(handler.triggerCount, 2)
    }
}

@MainActor
private final class FakeHotkeyHandler: HotkeyTriggerHandling {
    var triggerCount = 0

    func handleHotkeyTrigger() {
        triggerCount += 1
    }
}
