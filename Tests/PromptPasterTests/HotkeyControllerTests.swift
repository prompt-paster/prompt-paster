import Carbon.HIToolbox
import XCTest
@testable import PromptPaster

@MainActor
final class HotkeyControllerTests: XCTestCase {
    func testDefaultFallbackShortcutIsControlOptionSpace() {
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.displayName, "Control + Option + Space")
        XCTAssertEqual(HotkeyDisplay.fallbackShortcut, "Control + Option + Space")
        XCTAssertEqual(HotkeyDisplay.doubleControlShortcut, "Double Control")
        XCTAssertEqual(HotkeyDisplay.doubleControlThreshold, "350 ms")
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
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        let status = try controller.start()

        XCTAssertEqual(registrar.installHandlerCount, 1)
        XCTAssertEqual(registrar.registerHotkeyCount, 1)
        XCTAssertEqual(registrar.registeredShortcut, .controlOptionSpace)
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertTrue(status.isDoubleControlActive)
    }

    func testStartIsIdempotentWhileRegistered() throws {
        let registrar = FakeHotkeyRegistrar()
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        try controller.start()
        try controller.start()

        XCTAssertEqual(registrar.installHandlerCount, 1)
        XCTAssertEqual(registrar.registerHotkeyCount, 1)
        XCTAssertEqual(monitor.startCount, 1)
    }

    func testStartRemovesHandlerWhenRegistrationFails() {
        let registrar = FakeHotkeyRegistrar(registrationError: HotkeyControllerError.registrationFailed(-9876))
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        XCTAssertThrowsError(try controller.start()) { error in
            XCTAssertEqual(error as? HotkeyControllerError, .registrationFailed(-9876))
        }
        XCTAssertEqual(registrar.installHandlerCount, 1)
        XCTAssertEqual(registrar.registerHotkeyCount, 1)
        XCTAssertEqual(registrar.removeHandlerCount, 1)
        XCTAssertEqual(registrar.unregisterHotkeyCount, 0)
        XCTAssertEqual(monitor.startCount, 0)
    }

    func testStopUnregistersHotkeyBeforeRemovingHandler() throws {
        let registrar = FakeHotkeyRegistrar()
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        try controller.start()
        controller.stop()

        XCTAssertEqual(registrar.unregisterHotkeyCount, 1)
        XCTAssertEqual(registrar.removeHandlerCount, 1)
        XCTAssertEqual(registrar.cleanupEvents, ["unregister-hotkey", "remove-handler"])
        XCTAssertEqual(monitor.stopCount, 1)
    }

    func testDeinitCleansUpRegisteredHotkeyAndHandler() throws {
        let registrar = FakeHotkeyRegistrar()
        let monitor = FakeDoubleControlMonitor()
        var controller: HotkeyController? = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        try controller?.start()
        controller = nil

        XCTAssertEqual(registrar.unregisterHotkeyCount, 1)
        XCTAssertEqual(registrar.removeHandlerCount, 1)
        XCTAssertEqual(registrar.cleanupEvents, ["unregister-hotkey", "remove-handler"])
    }

    func testDoubleControlDoesNotStartWithoutAccessibilityPermission() throws {
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(FakeHotkeyRegistrar()),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: false)
        )

        let status = try controller.start()

        XCTAssertFalse(status.isDoubleControlActive)
        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertTrue(status.doubleControlStatusMessage?.contains("Accessibility permission") == true)
    }

    func testDoubleControlMonitorTriggersSameHandlerRoute() throws {
        let handler = FakeHotkeyHandler()
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            handler: handler,
            registrar: AnyHotkeyRegistrar(FakeHotkeyRegistrar()),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true),
            doubleControlConfiguration: DoubleControlTapConfiguration(
                tapThreshold: 0.35,
                debounceInterval: 0.45
            )
        )

        try controller.start()
        monitor.send(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.0))
        monitor.send(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.05))
        monitor.send(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.20))
        monitor.send(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.25))

        XCTAssertEqual(handler.triggerCount, 1)
    }

    func testDoubleControlDetectorRequiresTwoCompletedTapsWithinThreshold() {
        var detector = DoubleControlTapDetector(configuration: DoubleControlTapConfiguration(
            tapThreshold: 0.35,
            debounceInterval: 0.45
        ))

        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.0)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.05)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.50)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.55)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.80)))
        XCTAssertTrue(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.85)))
    }

    func testDoubleControlDetectorIgnoresUnrelatedInterruptions() {
        var detector = DoubleControlTapDetector()

        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.0)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.05)))
        XCTAssertFalse(detector.handle(.unrelatedInput(timestamp: 1.10)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.20)))
        XCTAssertTrue(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.25)))
    }

    func testDoubleControlDetectorIgnoresControlTapWithOtherModifiersHeld() {
        var detector = DoubleControlTapDetector()

        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: true, timestamp: 1.0)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: true, timestamp: 1.05)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.20)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.25)))
    }

    func testDoubleControlDetectorDebouncesAfterTrigger() {
        var detector = DoubleControlTapDetector(configuration: DoubleControlTapConfiguration(
            tapThreshold: 0.35,
            debounceInterval: 0.45
        ))

        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.0)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.05)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.20)))
        XCTAssertTrue(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.25)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.30)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.35)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.80)))
        XCTAssertFalse(detector.handle(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.85)))
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

@MainActor
private final class FakeDoubleControlMonitor: DoubleControlMonitoring {
    var startCount = 0
    var stopCount = 0
    private var eventHandler: (@MainActor (DoubleControlTapInput) -> Void)?

    func start(eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void) throws {
        startCount += 1
        self.eventHandler = eventHandler
    }

    func stop() {
        stopCount += 1
        eventHandler = nil
    }

    func send(_ input: DoubleControlTapInput) {
        eventHandler?(input)
    }
}

private struct FakeAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    let isAccessibilityTrusted: Bool

    func openAccessibilitySettings() {}
}
