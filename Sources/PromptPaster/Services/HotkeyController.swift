import Carbon.HIToolbox
import AppKit
import Foundation

private let promptPasterHotKeySignature: OSType = 0x5050_484B
private let promptPasterFallbackHotKeyID: UInt32 = 1

enum HotkeyDisplay {
    static let fallbackShortcut = HotkeyShortcut.controlOptionSpace.displayName
    static let doubleControlShortcut = "Double Control"
    static let doubleControlThreshold = "350 ms"
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
    var doubleControlStatusMessage: String?
    var isDoubleControlActive: Bool

    static let fallbackOnly = HotkeyStartupStatus(
        fallbackHotkeyStatusMessage: nil,
        doubleControlStatusMessage: nil,
        isDoubleControlActive: false
    )
}

protocol AccessibilityPermissionChecking {
    var isAccessibilityTrusted: Bool { get }
    func openAccessibilitySettings()
}

struct AccessibilityPermissionChecker: AccessibilityPermissionChecking {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
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
    func start(eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void) throws
    func stop()
}

@MainActor
final class HotkeyController {
    private let shortcut: HotkeyShortcut
    private let router: HotkeyTriggerRouter
    private let registrationState: HotkeyRegistrationState
    private let doubleControlMonitor: DoubleControlMonitoring
    private let accessibilityPermissionChecker: AccessibilityPermissionChecking
    private var doubleControlDetector: DoubleControlTapDetector

    init(
        shortcut: HotkeyShortcut = .controlOptionSpace,
        handler: HotkeyTriggerHandling,
        registrar: AnyHotkeyRegistrar = AnyHotkeyRegistrar(CarbonHotkeyRegistrar()),
        doubleControlMonitor: DoubleControlMonitoring = CGEventDoubleControlMonitor(),
        accessibilityPermissionChecker: AccessibilityPermissionChecking = AccessibilityPermissionChecker(),
        doubleControlConfiguration: DoubleControlTapConfiguration = .default
    ) {
        self.shortcut = shortcut
        self.router = HotkeyTriggerRouter(handler: handler)
        self.registrationState = HotkeyRegistrationState(registrar: registrar)
        self.doubleControlMonitor = doubleControlMonitor
        self.accessibilityPermissionChecker = accessibilityPermissionChecker
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

        return startDoubleControlMonitoring()
    }

    func stop() {
        registrationState.stop()
        doubleControlMonitor.stop()
    }

    func openAccessibilitySettings() {
        accessibilityPermissionChecker.openAccessibilitySettings()
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

    private func startDoubleControlMonitoring() -> HotkeyStartupStatus {
        guard accessibilityPermissionChecker.isAccessibilityTrusted else {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatusMessage: "Double Control needs Accessibility permission. Grant permission in System Settings, then relaunch Prompt Paster. The fallback hotkey remains available.",
                isDoubleControlActive: false
            )
        }

        do {
            try doubleControlMonitor.start { [weak self] input in
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
                doubleControlStatusMessage: nil,
                isDoubleControlActive: true
            )
        } catch {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatusMessage: "Double Control unavailable. \(error.localizedDescription)",
                isDoubleControlActive: false
            )
        }
    }

    private func statusForCurrentDoubleControlPermission() -> HotkeyStartupStatus {
        guard accessibilityPermissionChecker.isAccessibilityTrusted else {
            return HotkeyStartupStatus(
                fallbackHotkeyStatusMessage: nil,
                doubleControlStatusMessage: "Double Control needs Accessibility permission. Grant permission in System Settings, then relaunch Prompt Paster. The fallback hotkey remains available.",
                isDoubleControlActive: false
            )
        }

        return HotkeyStartupStatus(
            fallbackHotkeyStatusMessage: nil,
            doubleControlStatusMessage: nil,
            isDoubleControlActive: true
        )
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
final class CGEventDoubleControlMonitor: DoubleControlMonitoring {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventHandler: (@MainActor (DoubleControlTapInput) -> Void)?

    func start(eventHandler: @escaping @MainActor (DoubleControlTapInput) -> Void) throws {
        guard eventTap == nil else {
            self.eventHandler = eventHandler
            return
        }

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
        switch type {
        case .flagsChanged:
            guard Self.isControlKeyEvent(event) else {
                eventHandler?(.unrelatedInput(timestamp: event.timestampSeconds))
                return
            }

            let flags = event.flags
            eventHandler?(
                .controlChanged(
                    isPressed: flags.contains(.maskControl),
                    otherModifiersPressed: Self.hasOtherModifier(in: flags),
                    timestamp: event.timestampSeconds
                )
            )
        case .keyDown:
            eventHandler?(.unrelatedInput(timestamp: event.timestampSeconds))
        default:
            break
        }
    }

    private static func isControlKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        return keyCode == CGKeyCode(kVK_Control) || keyCode == CGKeyCode(kVK_RightControl)
    }

    private static func hasOtherModifier(in flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate)
            || flags.contains(.maskCommand)
            || flags.contains(.maskShift)
            || flags.contains(.maskSecondaryFn)
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
