import Carbon.HIToolbox
import AppKit
import Foundation
import IOKit.hid

private let promptPasterHotKeySignature: OSType = 0x5050_484B
private let promptPasterFallbackHotKeyID: UInt32 = 1

enum HotkeyDisplay {
    static let fallbackShortcut = HotkeyShortcut.controlOptionSpace.displayName
    static let doubleControlShortcut = "Double Control"

    static func doubleControlThreshold(_ milliseconds: Int) -> String {
        "\(milliseconds) ms"
    }
}

enum FallbackHotkeyPreset: String, CaseIterable, Identifiable {
    case controlOptionSpace
    case controlOptionP
    case controlOptionReturn
    case controlShiftSpace
    case commandOptionSpace

    var id: String {
        rawValue
    }

    var shortcut: HotkeyShortcut {
        switch self {
        case .controlOptionSpace:
            .controlOptionSpace
        case .controlOptionP:
            HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_P),
                modifiers: UInt32(controlKey | optionKey),
                displayName: "Control + Option + P"
            )
        case .controlOptionReturn:
            HotkeyShortcut(
                keyCode: UInt32(kVK_Return),
                modifiers: UInt32(controlKey | optionKey),
                displayName: "Control + Option + Return"
            )
        case .controlShiftSpace:
            HotkeyShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey | shiftKey),
                displayName: "Control + Shift + Space"
            )
        case .commandOptionSpace:
            HotkeyShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(cmdKey | optionKey),
                displayName: "Command + Option + Space"
            )
        }
    }

    var displayName: String {
        shortcut.displayName
    }
}

enum DoubleTapModifier: String, CaseIterable, Identifiable {
    case control
    case option
    case shift
    case command

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .control:
            "Control"
        case .option:
            "Option"
        case .shift:
            "Shift"
        case .command:
            "Command"
        }
    }

    var doubleTapDisplayName: String {
        "Double \(displayName)"
    }

    var keyCodes: Set<CGKeyCode> {
        switch self {
        case .control:
            [CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl)]
        case .option:
            [CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption)]
        case .shift:
            [CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift)]
        case .command:
            [CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand)]
        }
    }

    var hidUsages: Set<Int> {
        switch self {
        case .control:
            [0xE0, 0xE4]
        case .shift:
            [0xE1, 0xE5]
        case .option:
            [0xE2, 0xE6]
        case .command:
            [0xE3, 0xE7]
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .control:
            .maskControl
        case .option:
            .maskAlternate
        case .shift:
            .maskShift
        case .command:
            .maskCommand
        }
    }

    var eventModifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .control:
            .control
        case .option:
            .option
        case .shift:
            .shift
        case .command:
            .command
        }
    }
}

struct HotkeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let controlOptionSpace = HotkeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey),
        displayName: "Control + Option + Space"
    )
}

@MainActor
protocol HotkeyTriggerHandling: AnyObject {
    func handleHotkeyTrigger()
}

@MainActor
final class HotkeyTriggerRouter {
    private weak var handler: HotkeyTriggerHandling?

    init(handler: HotkeyTriggerHandling) {
        self.handler = handler
    }

    func handleTrigger() {
        handler?.handleHotkeyTrigger()
    }
}

enum HotkeyControllerError: Error, LocalizedError, Equatable {
    case handlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)
    case doubleControlMonitorFailed

    var errorDescription: String? {
        switch self {
        case let .handlerInstallFailed(status):
            "Could not install global hotkey handler. OSStatus \(status)."
        case let .registrationFailed(status):
            "Could not register Control + Option + Space. OSStatus \(status)."
        case .doubleControlMonitorFailed:
            "Could not start double-Control monitoring."
        }
    }
}

enum DoubleControlTapInput: Equatable {
    case controlChanged(isPressed: Bool, otherModifiersPressed: Bool, timestamp: TimeInterval)
    case unrelatedInput(timestamp: TimeInterval)
}

struct DoubleControlTapConfiguration: Equatable {
    var tapThreshold: TimeInterval
    var debounceInterval: TimeInterval

    static let `default` = DoubleControlTapConfiguration(
        tapThreshold: 0.35,
        debounceInterval: 0.45
    )
}

struct DoubleControlTapDetector {
    private let configuration: DoubleControlTapConfiguration
    private var isTrackingControlDown = false
    private var lastTapTimestamp: TimeInterval?
    private var debouncedUntil: TimeInterval?

    init(configuration: DoubleControlTapConfiguration = .default) {
        self.configuration = configuration
    }

    mutating func handle(_ input: DoubleControlTapInput) -> Bool {
        switch input {
        case let .controlChanged(isPressed, otherModifiersPressed, timestamp):
            return handleControlChanged(
                isPressed: isPressed,
                otherModifiersPressed: otherModifiersPressed,
                timestamp: timestamp
            )
        case .unrelatedInput:
            return false
        }
    }

    private mutating func handleControlChanged(
        isPressed: Bool,
        otherModifiersPressed: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        if let debouncedUntil, timestamp < debouncedUntil {
            isTrackingControlDown = false
            return false
        }

        if isPressed {
            isTrackingControlDown = !otherModifiersPressed
            return false
        }

        guard isTrackingControlDown, !otherModifiersPressed else {
            isTrackingControlDown = false
            return false
        }

        isTrackingControlDown = false

        if let lastTapTimestamp,
           timestamp - lastTapTimestamp <= configuration.tapThreshold {
            self.lastTapTimestamp = nil
            debouncedUntil = timestamp + configuration.debounceInterval
            return true
        }

        lastTapTimestamp = timestamp
        return false
    }
}

struct HotkeyStartupStatus: Equatable {
    var fallbackHotkeyStatusMessage: String?
    var doubleControlStatus: DoubleControlTriggerStatus

    static let fallbackOnly = HotkeyStartupStatus(
        fallbackHotkeyStatusMessage: nil,
        doubleControlStatus: .needsAccessibility
    )
}

enum DoubleControlTriggerStatus: Equatable {
    case active
    case disabled
    case needsAccessibility
    case needsInputMonitoring
    case monitorUnavailable(String)

    var displayValue: String {
        switch self {
        case .active:
            "Active"
        case .disabled:
            "Disabled"
        case .needsAccessibility:
            "Needs Accessibility"
        case .needsInputMonitoring:
            "Needs Input Monitoring"
        case .monitorUnavailable:
            "Unavailable"
        }
    }

    var message: String? {
        switch self {
        case .active:
            nil
        case .disabled:
            "Double Control is disabled. The fallback hotkey remains available."
        case .needsAccessibility:
            "Double Control needs Accessibility permission. Grant permission in System Settings, then recheck permission. The fallback hotkey remains available."
        case .needsInputMonitoring:
            "Double Control needs Input Monitoring permission. Grant permission in System Settings, then recheck permission. The fallback hotkey remains available."
        case let .monitorUnavailable(message):
            message
        }
    }

    var canRequestAccessibilityPermission: Bool {
        self == .needsAccessibility
    }

    var canRequestInputMonitoringPermission: Bool {
        self == .needsInputMonitoring
    }
}

protocol AccessibilityPermissionChecking {
    var isAccessibilityTrusted: Bool { get }
    var isInputMonitoringTrusted: Bool { get }
    @discardableResult
    func requestAccessibilityPermission() -> Bool
    @discardableResult
    func requestInputMonitoringPermission() -> Bool
    func openAccessibilitySettings()
    func openInputMonitoringSettings()
}

struct AccessibilityPermissionChecker: AccessibilityPermissionChecking {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var isInputMonitoringTrusted: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

protocol HotkeyRegistrar {
    associatedtype HandlerToken
    associatedtype HotkeyToken

    func installHandler(
        target: HotkeyController,
        callback: EventHandlerUPP
    ) throws -> HandlerToken

    func registerHotkey(
        shortcut: HotkeyShortcut,
        signature: OSType,
        id: UInt32
    ) throws -> HotkeyToken

    func removeHandler(_ token: HandlerToken)
    func unregisterHotkey(_ token: HotkeyToken)
}

@MainActor
protocol DoubleControlMonitoring: AnyObject {
    var isRunning: Bool { get }

    func start(
        modifier: DoubleTapModifier,
        eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void
    ) throws
    func stop()
}

@MainActor
final class HotkeyController {
    private let shortcut: HotkeyShortcut
    private let triggerMode: TriggerMode
    private let doubleTapModifier: DoubleTapModifier
    private let router: HotkeyTriggerRouter
    private let registrationState: HotkeyRegistrationState
    private let doubleControlMonitor: DoubleControlMonitoring
    private let accessibilityPermissionChecker: AccessibilityPermissionChecking
    private var doubleControlDetector: DoubleControlTapDetector
    private var doubleControlConfiguration: DoubleControlTapConfiguration

    init(
        shortcut: HotkeyShortcut = .controlOptionSpace,
        triggerMode: TriggerMode = .doubleControlWithFallback,
        doubleTapModifier: DoubleTapModifier = .control,
        handler: HotkeyTriggerHandling,
        registrar: AnyHotkeyRegistrar = AnyHotkeyRegistrar(CarbonHotkeyRegistrar()),
        doubleControlMonitor: DoubleControlMonitoring = ResilientDoubleControlMonitor(),
        accessibilityPermissionChecker: AccessibilityPermissionChecking = AccessibilityPermissionChecker(),
        doubleControlConfiguration: DoubleControlTapConfiguration = .default
    ) {
        self.shortcut = shortcut
        self.triggerMode = triggerMode
        self.doubleTapModifier = doubleTapModifier
        self.router = HotkeyTriggerRouter(handler: handler)
        self.registrationState = HotkeyRegistrationState(registrar: registrar)
        self.doubleControlMonitor = doubleControlMonitor
        self.accessibilityPermissionChecker = accessibilityPermissionChecker
        self.doubleControlConfiguration = doubleControlConfiguration
        self.doubleControlDetector = DoubleControlTapDetector(configuration: doubleControlConfiguration)
    }

    @discardableResult
    func start() throws -> HotkeyStartupStatus {
        guard !registrationState.isRegistered else {
            return statusForCurrentDoubleControlPermission()
        }

        if !registrationState.hasHandler {
            try installEventHandler()
        }

        do {
            registrationState.hotKeyRef = try registrationState.registrar.registerHotkey(
                shortcut: shortcut,
                signature: promptPasterHotKeySignature,
                id: promptPasterFallbackHotKeyID
            )
        } catch {
            registrationState.removeHandler()
            throw error
        }

        return startDoubleControlMonitoringIfEnabled()
    }

    func stop() {
        registrationState.stop()
        doubleControlMonitor.stop()
    }

    func openAccessibilitySettings() {
        accessibilityPermissionChecker.openAccessibilitySettings()
    }

    func openInputMonitoringSettings() {
        accessibilityPermissionChecker.openInputMonitoringSettings()
    }

    func updateDoubleControlConfiguration(_ configuration: DoubleControlTapConfiguration) {
        doubleControlConfiguration = configuration
        doubleControlDetector = DoubleControlTapDetector(configuration: configuration)
    }

    @discardableResult
    func requestAccessibilityPermission() -> HotkeyStartupStatus {
        accessibilityPermissionChecker.requestAccessibilityPermission()
        return recheckPermissionsAndStartMonitoring()
    }

    @discardableResult
    func requestInputMonitoringPermission() -> HotkeyStartupStatus {
        accessibilityPermissionChecker.requestInputMonitoringPermission()
        return recheckPermissionsAndStartMonitoring()
    }

    private func recheckPermissionsAndStartMonitoring() -> HotkeyStartupStatus {
        guard registrationState.isRegistered else {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: "Fallback hotkey has not started.",
                doubleControlStatus: .monitorUnavailable("Double Control not started because fallback hotkey registration is not active.")
            )
        }

        return startDoubleControlMonitoringIfEnabled()
    }

    fileprivate func handleRegisteredHotkey() {
        router.handleTrigger()
    }

    private func installEventHandler() throws {
        registrationState.eventHandlerRef = try registrationState.registrar.installHandler(
            target: self,
            callback: promptPasterHotKeyHandler
        )
    }

    private func startDoubleControlMonitoringIfEnabled() -> HotkeyStartupStatus {
        guard triggerMode == .doubleControlWithFallback else {
            doubleControlMonitor.stop()
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .disabled
            )
        }

        if doubleControlMonitor.isRunning {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .active
            )
        }

        guard accessibilityPermissionChecker.isAccessibilityTrusted else {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .needsAccessibility
            )
        }

        do {
            try doubleControlMonitor.start(modifier: doubleTapModifier) { [weak self] input in
                guard var detector = self?.doubleControlDetector else {
                    return
                }

                let shouldTrigger = detector.handle(input)
                self?.doubleControlDetector = detector

                if shouldTrigger {
                    self?.router.handleTrigger()
                }
            }
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .active
            )
        } catch {
            if !accessibilityPermissionChecker.isInputMonitoringTrusted {
                return HotkeyStartupStatus(
                    fallbackHotkeyStatusMessage: nil,
                    doubleControlStatus: .needsInputMonitoring
                )
            }
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .monitorUnavailable("Double Control unavailable. \(error.localizedDescription)")
            )
        }
    }

    private func statusForCurrentDoubleControlPermission() -> HotkeyStartupStatus {
        guard triggerMode == .doubleControlWithFallback else {
            doubleControlMonitor.stop()
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .disabled
            )
        }

        if doubleControlMonitor.isRunning {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .active
            )
        }

        guard accessibilityPermissionChecker.isAccessibilityTrusted else {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatus: .needsAccessibility
            )
        }

        return startDoubleControlMonitoringIfEnabled()
    }
}

private final class HotkeyRegistrationState {
    let registrar: AnyHotkeyRegistrar
    var eventHandlerRef: Any?
    var hotKeyRef: Any?

    var hasHandler: Bool {
        eventHandlerRef != nil
    }

    var isRegistered: Bool {
        hotKeyRef != nil
    }

    init(registrar: AnyHotkeyRegistrar) {
        self.registrar = registrar
    }

    deinit {
        stop()
    }

    func stop() {
        if let hotKeyRef {
            registrar.unregisterHotkey(hotKeyRef)
        }
        hotKeyRef = nil

        removeHandler()
    }

    func removeHandler() {
        if let eventHandlerRef {
            registrar.removeHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
    }
}

struct CarbonHotkeyRegistrar: HotkeyRegistrar {
    func installHandler(
        target: HotkeyController,
        callback: EventHandlerUPP
    ) throws -> EventHandlerRef {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(target).toOpaque(),
            &installedHandlerRef
        )

        guard status == noErr, let installedHandlerRef else {
            throw HotkeyControllerError.handlerInstallFailed(status)
        }

        return installedHandlerRef
    }

    func registerHotkey(
        shortcut: HotkeyShortcut,
        signature: OSType,
        id: UInt32
    ) throws -> EventHotKeyRef {
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var registeredHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKeyRef
        )

        guard status == noErr, let registeredHotKeyRef else {
            throw HotkeyControllerError.registrationFailed(status)
        }

        return registeredHotKeyRef
    }

    func removeHandler(_ token: EventHandlerRef) {
        RemoveEventHandler(token)
    }

    func unregisterHotkey(_ token: EventHotKeyRef) {
        UnregisterEventHotKey(token)
    }
}

@MainActor
final class ResilientDoubleControlMonitor: DoubleControlMonitoring {
    private let monitors: [DoubleControlMonitoring]
    private var activeMonitor: DoubleControlMonitoring?

    var isRunning: Bool {
        activeMonitor?.isRunning ?? false
    }

    init(monitors: [DoubleControlMonitoring] = [
        IOHIDDoubleControlMonitor(),
        CGEventDoubleControlMonitor(),
        NSEventDoubleControlMonitor()
    ]) {
        self.monitors = monitors
    }

    func start(
        modifier: DoubleTapModifier,
        eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void
    ) throws {
        if let activeMonitor {
            try activeMonitor.start(modifier: modifier, eventHandler: eventHandler)
            return
        }

        for monitor in monitors {
            do {
                try monitor.start(modifier: modifier, eventHandler: eventHandler)
                activeMonitor = monitor
                return
            } catch {
                monitor.stop()
            }
        }

        throw HotkeyControllerError.doubleControlMonitorFailed
    }

    func stop() {
        activeMonitor?.stop()
        activeMonitor = nil
    }
}

@MainActor
final class IOHIDDoubleControlMonitor: DoubleControlMonitoring {
    private let keyboardUsagePage = 0x07
    private var manager: IOHIDManager?
    private var eventHandler: (@MainActor (DoubleControlTapInput) -> Void)?
    private var modifier: DoubleTapModifier = .control
    private var pressedModifierUsages: Set<Int> = []

    var isRunning: Bool {
        manager != nil
    }

    func start(
        modifier: DoubleTapModifier,
        eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void
    ) throws {
        guard manager == nil else {
            self.modifier = modifier
            self.eventHandler = eventHandler
            return
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]

        IOHIDManagerSetDeviceMatching(manager, keyboardMatch as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, _, _, value in
                guard let context else {
                    return
                }
                let monitor = Unmanaged<IOHIDDoubleControlMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                Task { @MainActor in
                    monitor.handle(value)
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            throw HotkeyControllerError.doubleControlMonitorFailed
        }

        self.modifier = modifier
        self.eventHandler = eventHandler
        self.manager = manager
        self.pressedModifierUsages = []
    }

    func stop() {
        guard let manager else {
            return
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        self.eventHandler = nil
        self.pressedModifierUsages = []
    }

    private func handle(_ value: IOHIDValue) {
        guard let input = DoubleControlEventInputMapper.input(
            for: value,
            pressedModifierUsages: &pressedModifierUsages,
            timestamp: ProcessInfo.processInfo.systemUptime,
            modifier: modifier
        ) else {
            return
        }
        eventHandler?(input)
    }
}

@MainActor
final class NSEventDoubleControlMonitor: DoubleControlMonitoring {
    private var monitors: [Any] = []
    private var eventHandler: (@MainActor (DoubleControlTapInput) -> Void)?
    private var modifier: DoubleTapModifier = .control

    var isRunning: Bool {
        !monitors.isEmpty
    }

    func start(
        modifier: DoubleTapModifier,
        eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void
    ) throws {
        guard monitors.isEmpty else {
            self.modifier = modifier
            self.eventHandler = eventHandler
            return
        }

        self.modifier = modifier
        self.eventHandler = eventHandler

        guard let flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }) else {
            throw HotkeyControllerError.doubleControlMonitorFailed
        }

        guard let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }) else {
            NSEvent.removeMonitor(flagsMonitor)
            throw HotkeyControllerError.doubleControlMonitorFailed
        }

        monitors = [flagsMonitor, keyMonitor]
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        eventHandler = nil
    }

    private func handle(_ event: NSEvent) {
        guard let input = DoubleControlEventInputMapper.input(
            for: event.type,
            keyCode: event.keyCode,
            flags: event.modifierFlags,
            timestamp: event.timestamp,
            modifier: modifier
        ) else {
            return
        }
        eventHandler?(input)
    }
}

@MainActor
final class CGEventDoubleControlMonitor: DoubleControlMonitoring {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventHandler: (@MainActor (DoubleControlTapInput) -> Void)?
    private var modifier: DoubleTapModifier = .control

    var isRunning: Bool {
        eventTap != nil
    }

    func start(eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void) throws {
        try start(modifier: .control, eventHandler: eventHandler)
    }

    func start(
        modifier: DoubleTapModifier,
        eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void
    ) throws {
        guard eventTap == nil else {
            self.modifier = modifier
            self.eventHandler = eventHandler
            return
        }

        self.modifier = modifier
        self.eventHandler = eventHandler

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<CGEventDoubleControlMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyControllerError.doubleControlMonitorFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            throw HotkeyControllerError.doubleControlMonitorFailed
        }

        self.eventTap = eventTap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        self.runLoopSource = nil
        self.eventTap = nil
        self.eventHandler = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if DoubleControlEventInputMapper.isDisabledTapEvent(type) {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let input = DoubleControlEventInputMapper.input(
            for: type,
            keyCode: keyCode,
            flags: event.flags,
            timestamp: event.timestampSeconds,
            modifier: modifier
        ) else {
            return
        }
        eventHandler?(input)
    }
}

enum DoubleControlEventInputMapper {
    static let hidModifierUsages: Set<Int> = [
        0xE0, 0xE1, 0xE2, 0xE3,
        0xE4, 0xE5, 0xE6, 0xE7
    ]

    static func input(
        for usagePage: Int,
        usage: Int,
        isPressed: Bool,
        pressedModifierUsages: inout Set<Int>,
        timestamp: TimeInterval,
        modifier: DoubleTapModifier = .control
    ) -> DoubleControlTapInput? {
        guard usagePage == 0x07, hidModifierUsages.contains(usage) else {
            return nil
        }

        if isPressed {
            pressedModifierUsages.insert(usage)
        } else {
            pressedModifierUsages.remove(usage)
        }

        guard modifier.hidUsages.contains(usage) else {
            return .unrelatedInput(timestamp: timestamp)
        }

        let otherModifiersPressed = pressedModifierUsages.contains { !modifier.hidUsages.contains($0) }
        return .controlChanged(
            isPressed: isPressed,
            otherModifiersPressed: otherModifiersPressed,
            timestamp: timestamp
        )
    }

    static func input(
        for value: IOHIDValue,
        pressedModifierUsages: inout Set<Int>,
        timestamp: TimeInterval,
        modifier: DoubleTapModifier = .control
    ) -> DoubleControlTapInput? {
        let element = IOHIDValueGetElement(value)
        return input(
            for: Int(IOHIDElementGetUsagePage(element)),
            usage: Int(IOHIDElementGetUsage(element)),
            isPressed: IOHIDValueGetIntegerValue(value) != 0,
            pressedModifierUsages: &pressedModifierUsages,
            timestamp: timestamp,
            modifier: modifier
        )
    }

    static func input(
        for type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        timestamp: TimeInterval,
        modifier: DoubleTapModifier = .control
    ) -> DoubleControlTapInput? {
        switch type {
        case .flagsChanged:
            guard modifier.keyCodes.contains(CGKeyCode(keyCode)) else {
                return .unrelatedInput(timestamp: timestamp)
            }
            return .controlChanged(
                isPressed: flags.contains(modifier.eventModifierFlag),
                otherModifiersPressed: hasOtherModifier(in: flags, excluding: modifier),
                timestamp: timestamp
            )
        case .keyDown:
            return .unrelatedInput(timestamp: timestamp)
        default:
            return nil
        }
    }

    static func input(
        for type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        timestamp: TimeInterval,
        modifier: DoubleTapModifier = .control
    ) -> DoubleControlTapInput? {
        switch type {
        case .flagsChanged:
            guard modifier.keyCodes.contains(keyCode) else {
                return .unrelatedInput(timestamp: timestamp)
            }
            return .controlChanged(
                isPressed: flags.contains(modifier.eventFlag),
                otherModifiersPressed: hasOtherModifier(in: flags, excluding: modifier),
                timestamp: timestamp
            )
        case .keyDown:
            return .unrelatedInput(timestamp: timestamp)
        default:
            return nil
        }
    }

    static func isDisabledTapEvent(_ type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }

    private static func hasOtherModifier(in flags: CGEventFlags, excluding modifier: DoubleTapModifier) -> Bool {
        let modifierFlags: [(DoubleTapModifier, CGEventFlags)] = [
            (.control, .maskControl),
            (.option, .maskAlternate),
            (.shift, .maskShift),
            (.command, .maskCommand)
        ]

        return modifierFlags.contains { candidate, flag in
            candidate != modifier && flags.contains(flag)
        } || flags.contains(.maskSecondaryFn)
    }

    private static func hasOtherModifier(in flags: NSEvent.ModifierFlags, excluding modifier: DoubleTapModifier) -> Bool {
        let modifierFlags: [(DoubleTapModifier, NSEvent.ModifierFlags)] = [
            (.control, .control),
            (.option, .option),
            (.shift, .shift),
            (.command, .command)
        ]

        return modifierFlags.contains { candidate, flag in
            candidate != modifier && flags.contains(flag)
        } || flags.contains(.function)
    }
}

private extension CGEvent {
    var timestampSeconds: TimeInterval {
        TimeInterval(timestamp) / 1_000_000_000
    }
}

struct AnyHotkeyRegistrar: HotkeyRegistrar {
    private let installHandlerClosure: (HotkeyController, EventHandlerUPP) throws -> Any
    private let registerHotkeyClosure: (HotkeyShortcut, OSType, UInt32) throws -> Any
    private let removeHandlerClosure: (Any) -> Void
    private let unregisterHotkeyClosure: (Any) -> Void

    init<Registrar: HotkeyRegistrar>(_ registrar: Registrar) {
        installHandlerClosure = { target, callback in
            try registrar.installHandler(target: target, callback: callback)
        }
        registerHotkeyClosure = { shortcut, signature, id in
            try registrar.registerHotkey(shortcut: shortcut, signature: signature, id: id)
        }
        removeHandlerClosure = { token in
            guard let typedToken = token as? Registrar.HandlerToken else {
                return
            }
            registrar.removeHandler(typedToken)
        }
        unregisterHotkeyClosure = { token in
            guard let typedToken = token as? Registrar.HotkeyToken else {
                return
            }
            registrar.unregisterHotkey(typedToken)
        }
    }

    func installHandler(
        target: HotkeyController,
        callback: EventHandlerUPP
    ) throws -> Any {
        try installHandlerClosure(target, callback)
    }

    func registerHotkey(
        shortcut: HotkeyShortcut,
        signature: OSType,
        id: UInt32
    ) throws -> Any {
        try registerHotkeyClosure(shortcut, signature, id)
    }

    func removeHandler(_ token: Any) {
        removeHandlerClosure(token)
    }

    func unregisterHotkey(_ token: Any) {
        unregisterHotkeyClosure(token)
    }
}

let promptPasterHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr,
          hotKeyID.signature == promptPasterHotKeySignature,
          hotKeyID.id == promptPasterFallbackHotKeyID
    else {
        return noErr
    }

    let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        Task { @MainActor in
            controller.handleRegisteredHotkey()
        }
    }
    return noErr
}
