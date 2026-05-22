import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let promptStore: PromptStore
    private let settingsStore: SettingsStore
    private let settingsChanged: () -> Void
    private let openAccessibilitySettings: () -> Void
    private let requestAccessibilityPermission: () -> Void
    var fallbackHotkeyStatusMessage: String? {
        didSet {
            refreshContentView()
        }
    }
    var doubleControlStatus: DoubleControlTriggerStatus {
        didSet {
            refreshContentView()
        }
    }

    init(
        promptStore: PromptStore,
        settingsStore: SettingsStore,
        fallbackHotkeyStatusMessage: String? = nil,
        doubleControlStatus: DoubleControlTriggerStatus = .needsAccessibility,
        settingsChanged: @escaping () -> Void = {},
        openAccessibilitySettings: @escaping () -> Void = {},
        requestAccessibilityPermission: @escaping () -> Void = {}
    ) {
        self.promptStore = promptStore
        self.settingsStore = settingsStore
        self.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        self.doubleControlStatus = doubleControlStatus
        self.settingsChanged = settingsChanged
        self.openAccessibilitySettings = openAccessibilitySettings
        self.requestAccessibilityPermission = requestAccessibilityPermission
    }

    func refreshLaunchAtLoginStatus() {
        settingsStore.refreshLaunchAtLoginStatus()
        refreshContentView()
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Prompt Paster Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: makeSettingsView())
        return window
    }

    private func refreshContentView() {
        window?.contentView = NSHostingView(rootView: makeSettingsView())
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(
            promptStore: promptStore,
            settingsStore: settingsStore,
            fallbackHotkeyStatusMessage: fallbackHotkeyStatusMessage,
            doubleControlStatus: doubleControlStatus,
            settingsChanged: settingsChanged,
            openAccessibilitySettings: openAccessibilitySettings,
            requestAccessibilityPermission: requestAccessibilityPermission
        )
    }
}
