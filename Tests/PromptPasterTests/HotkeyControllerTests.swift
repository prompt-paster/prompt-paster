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

    func testStartInstallsHandlerAndRegistersHotkey() throws {
        let registrar = FakeHotkeyRegistrar()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar)
        )

        try controller.start()

        XCTAssertEqual(registrar.installHandlerCount, 1)
        XCTAssertEqual(registrar.registerHotkeyCount, 1)
        XCTAssertEqual(registrar.registeredShortcut, .controlOptionSpace)
    }

    func testStartIsIdempotentWhileRegistered() throws {
        let registrar = FakeHotkeyRegistrar()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar)
        )

        try controller.start()
        try controller.start()

        XCTAssertEqual(registrar.installHandlerCount, 1)
        XCTAssertEqual(registrar.registerHotkeyCount, 1)
    }

    func testStartRemovesHandlerWhenRegistrationFails() {
        let registrar = FakeHotkeyRegistrar(registrationError: HotkeyControllerError.registrationFailed(-9876))
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar)
        )

        XCTAssertThrowsError(try controller.start()) { error in
            XCTAssertEqual(error as? HotkeyControllerError, .registrationFailed(-9876))
        }
        XCTAssertEqual(registrar.installHandlerCount, 1)
        XCTAssertEqual(registrar.registerHotkeyCount, 1)
        XCTAssertEqual(registrar.removeHandlerCount, 1)
        XCTAssertEqual(registrar.unregisterHotkeyCount, 0)
    }

    func testStopUnregistersHotkeyBeforeRemovingHandler() throws {
        let registrar = FakeHotkeyRegistrar()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar)
        )

        try controller.start()
        controller.stop()

        XCTAssertEqual(registrar.unregisterHotkeyCount, 1)
        XCTAssertEqual(registrar.removeHandlerCount, 1)
        XCTAssertEqual(registrar.cleanupEvents, ["unregister-hotkey", "remove-handler"])
    }

    func testDeinitCleansUpRegisteredHotkeyAndHandler() throws {
        let registrar = FakeHotkeyRegistrar()
        var controller: HotkeyController? = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar)
        )

        try controller?.start()
        controller = nil

        XCTAssertEqual(registrar.unregisterHotkeyCount, 1)
        XCTAssertEqual(registrar.removeHandlerCount, 1)
        XCTAssertEqual(registrar.cleanupEvents, ["unregister-hotkey", "remove-handler"])
    }
}

@MainActor
private final class FakeHotkeyHandler: HotkeyTriggerHandling {
    var triggerCount = 0

    func handleHotkeyTrigger() {
        triggerCount += 1
    }
}

private final class FakeHotkeyRegistrar: HotkeyRegistrar {
    struct HandlerToken: Equatable {}
    struct HotkeyToken: Equatable {}

    var installHandlerCount = 0
    var registerHotkeyCount = 0
    var removeHandlerCount = 0
    var unregisterHotkeyCount = 0
    var registeredShortcut: HotkeyShortcut?
    var cleanupEvents: [String] = []

    private let handlerError: Error?
    private let registrationError: Error?

    init(handlerError: Error? = nil, registrationError: Error? = nil) {
        self.handlerError = handlerError
        self.registrationError = registrationError
    }

    func installHandler(
        target: HotkeyController,
        callback: EventHandlerUPP
    ) throws -> HandlerToken {
        installHandlerCount += 1

        if let handlerError {
            throw handlerError
        }

        return HandlerToken()
    }

    func registerHotkey(
        shortcut: HotkeyShortcut,
        signature: OSType,
        id: UInt32
    ) throws -> HotkeyToken {
        registerHotkeyCount += 1
        registeredShortcut = shortcut

        if let registrationError {
            throw registrationError
        }

        return HotkeyToken()
    }

    func removeHandler(_ token: HandlerToken) {
        removeHandlerCount += 1
        cleanupEvents.append("remove-handler")
    }

    func unregisterHotkey(_ token: HotkeyToken) {
        unregisterHotkeyCount += 1
        cleanupEvents.append("unregister-hotkey")
    }
}
