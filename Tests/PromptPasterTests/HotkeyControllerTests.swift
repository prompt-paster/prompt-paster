import Carbon.HIToolbox
import XCTest
@testable import PromptPaster

@MainActor
final class HotkeyControllerTests: XCTestCase {
    func testDefaultFallbackShortcutIsControlOptionSpace() {
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(HotkeyShortcut.controlOptionSpace.displayName, "Control + Option + Space")
        XCTAssertEqual(FallbackHotkeyPreset.controlOptionP.shortcut.keyCode, UInt32(kVK_ANSI_P))
        XCTAssertEqual(FallbackHotkeyPreset.controlOptionP.displayName, "Control + Option + P")
        XCTAssertEqual(DoubleTapModifier.option.doubleTapDisplayName, "Double Option")
        XCTAssertEqual(HotkeyDisplay.fallbackShortcut, "Control + Option + Space")
        XCTAssertEqual(HotkeyDisplay.doubleControlShortcut, "Double Control")
        XCTAssertEqual(HotkeyDisplay.doubleControlThreshold(350), "350 ms")
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
        XCTAssertEqual(status.doubleControlStatus, .active)
    }

    func testStartUsesConfiguredFallbackShortcutAndDoubleTapModifier() throws {
        let registrar = FakeHotkeyRegistrar()
        let monitor = FakeDoubleControlMonitor()
        let handler = FakeHotkeyHandler()
        let controller = HotkeyController(
            shortcut: FallbackHotkeyPreset.controlOptionP.shortcut,
            doubleTapModifier: .option,
            handler: handler,
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        try controller.start()
        monitor.send(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.0))
        monitor.send(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.05))
        monitor.send(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.20))
        monitor.send(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.25))

        XCTAssertEqual(registrar.registeredShortcut, FallbackHotkeyPreset.controlOptionP.shortcut)
        XCTAssertEqual(monitor.startedModifiers, [.option])
        XCTAssertEqual(handler.triggerCount, 1)
    }

    func testFallbackOnlyModeRegistersHotkeyWithoutStartingDoubleControlMonitor() throws {
        let registrar = FakeHotkeyRegistrar()
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            triggerMode: .fallbackHotkeyOnly,
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        let status = try controller.start()

        XCTAssertEqual(registrar.registerHotkeyCount, 1)
        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertEqual(status.doubleControlStatus, .disabled)
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

    func testStartRetriesDoubleControlWhenFallbackIsRegisteredButMonitorIsNotRunning() throws {
        let registrar = FakeHotkeyRegistrar()
        let monitor = FakeDoubleControlMonitor(startError: HotkeyControllerError.doubleControlMonitorFailed)
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(registrar),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true)
        )

        let firstStatus = try controller.start()
        monitor.startError = nil
        let secondStatus = try controller.start()

        XCTAssertEqual(firstStatus.doubleControlStatus, .monitorUnavailable("Double Control unavailable. Could not start double-Control monitoring."))
        XCTAssertEqual(secondStatus.doubleControlStatus, .active)
        XCTAssertEqual(registrar.registerHotkeyCount, 1)
        XCTAssertEqual(monitor.startCount, 2)
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

        XCTAssertEqual(status.doubleControlStatus, .needsAccessibility)
        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertTrue(status.doubleControlStatus.message?.contains("Accessibility permission") == true)
    }

    func testRequestAccessibilityPermissionRechecksAndStartsMonitor() throws {
        let monitor = FakeDoubleControlMonitor()
        let permissionChecker = FakeAccessibilityPermissionChecker(isAccessibilityTrusted: false)
        let controller = HotkeyController(
            handler: FakeHotkeyHandler(),
            registrar: AnyHotkeyRegistrar(FakeHotkeyRegistrar()),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: permissionChecker
        )

        XCTAssertEqual(try controller.start().doubleControlStatus, .needsAccessibility)
        permissionChecker.isAccessibilityTrusted = true
        let status = controller.requestAccessibilityPermission()

        XCTAssertEqual(permissionChecker.requestCount, 1)
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(status.doubleControlStatus, .active)
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

    func testUpdatingDoubleControlConfigurationResetsDetectorWithNewThreshold() throws {
        let handler = FakeHotkeyHandler()
        let monitor = FakeDoubleControlMonitor()
        let controller = HotkeyController(
            handler: handler,
            registrar: AnyHotkeyRegistrar(FakeHotkeyRegistrar()),
            doubleControlMonitor: monitor,
            accessibilityPermissionChecker: FakeAccessibilityPermissionChecker(isAccessibilityTrusted: true),
            doubleControlConfiguration: DoubleControlTapConfiguration(
                tapThreshold: 0.25,
                debounceInterval: 0.45
            )
        )

        try controller.start()
        controller.updateDoubleControlConfiguration(DoubleControlTapConfiguration(
            tapThreshold: 0.50,
            debounceInterval: 0.45
        ))
        monitor.send(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.0))
        monitor.send(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.05))
        monitor.send(.controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 1.45))
        monitor.send(.controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 1.50))

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

    func testDoubleControlEventMapperMapsLeftAndRightControlFlagsChanged() {
        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .flagsChanged,
                keyCode: CGKeyCode(kVK_Control),
                flags: .maskControl,
                timestamp: 2.0
            ),
            .controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 2.0)
        )

        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .flagsChanged,
                keyCode: CGKeyCode(kVK_RightControl),
                flags: [],
                timestamp: 2.1
            ),
            .controlChanged(isPressed: false, otherModifiersPressed: false, timestamp: 2.1)
        )
    }

    func testDoubleControlEventMapperFlagsOtherModifiers() {
        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .flagsChanged,
                keyCode: CGKeyCode(kVK_Control),
                flags: [.maskControl, .maskAlternate],
                timestamp: 3.0
            ),
            .controlChanged(isPressed: true, otherModifiersPressed: true, timestamp: 3.0)
        )
    }

    func testDoubleControlEventMapperSupportsConfiguredModifiers() {
        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .flagsChanged,
                keyCode: CGKeyCode(kVK_Option),
                flags: .maskAlternate,
                timestamp: 6.0,
                modifier: .option
            ),
            .controlChanged(isPressed: true, otherModifiersPressed: false, timestamp: 6.0)
        )
        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .flagsChanged,
                keyCode: CGKeyCode(kVK_Control),
                flags: .maskControl,
                timestamp: 6.1,
                modifier: .option
            ),
            .unrelatedInput(timestamp: 6.1)
        )
        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .flagsChanged,
                keyCode: CGKeyCode(kVK_Option),
                flags: [.maskAlternate, .maskControl],
                timestamp: 6.2,
                modifier: .option
            ),
            .controlChanged(isPressed: true, otherModifiersPressed: true, timestamp: 6.2)
        )
    }

    func testDoubleControlEventMapperTreatsNonControlModifierAndKeyDownAsInterruptions() {
        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .flagsChanged,
                keyCode: CGKeyCode(kVK_Option),
                flags: .maskAlternate,
                timestamp: 4.0
            ),
            .unrelatedInput(timestamp: 4.0)
        )
        XCTAssertEqual(
            DoubleControlEventInputMapper.input(
                for: .keyDown,
                keyCode: CGKeyCode(kVK_ANSI_A),
                flags: [],
                timestamp: 4.1
            ),
            .unrelatedInput(timestamp: 4.1)
        )
    }

    func testDoubleControlEventMapperIdentifiesDisabledTapEvents() {
        XCTAssertTrue(DoubleControlEventInputMapper.isDisabledTapEvent(.tapDisabledByTimeout))
        XCTAssertTrue(DoubleControlEventInputMapper.isDisabledTapEvent(.tapDisabledByUserInput))
        XCTAssertFalse(DoubleControlEventInputMapper.isDisabledTapEvent(.flagsChanged))
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
    var startedModifiers: [DoubleTapModifier] = []
    var startError: Error?
    private var eventHandler: (@MainActor (DoubleControlTapInput) -> Void)?

    var isRunning: Bool {
        eventHandler != nil
    }

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start(
        modifier: DoubleTapModifier,
        eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void
    ) throws {
        startCount += 1
        startedModifiers.append(modifier)
        if let startError {
            throw startError
        }
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

private final class FakeAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    var isAccessibilityTrusted: Bool
    var requestCount = 0

    init(isAccessibilityTrusted: Bool) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    func requestAccessibilityPermission() -> Bool {
        requestCount += 1
        return isAccessibilityTrusted
    }

    func openAccessibilitySettings() {}
}
