import Carbon.HIToolbox
import Foundation

private let promptPasterHotKeySignature: OSType = 0x5050_484B
private let promptPasterFallbackHotKeyID: UInt32 = 1

enum HotkeyDisplay {
    static let fallbackShortcut = HotkeyShortcut.controlOptionSpace.displayName
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

    var errorDescription: String? {
        switch self {
        case let .handlerInstallFailed(status):
            "Could not install global hotkey handler. OSStatus \(status)."
        case let .registrationFailed(status):
            "Could not register Control + Option + Space. OSStatus \(status)."
        }
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
final class HotkeyController {
    private let shortcut: HotkeyShortcut
    private let router: HotkeyTriggerRouter
    private let registrationState: HotkeyRegistrationState

    init(
        shortcut: HotkeyShortcut = .controlOptionSpace,
        handler: HotkeyTriggerHandling,
        registrar: AnyHotkeyRegistrar = AnyHotkeyRegistrar(CarbonHotkeyRegistrar())
    ) {
        self.shortcut = shortcut
        self.router = HotkeyTriggerRouter(handler: handler)
        self.registrationState = HotkeyRegistrationState(registrar: registrar)
    }

    func start() throws {
        guard !registrationState.isRegistered else {
            return
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
    }

    func stop() {
        registrationState.stop()
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
