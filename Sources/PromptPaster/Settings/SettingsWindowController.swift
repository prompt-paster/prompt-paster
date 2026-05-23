import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let promptStore: PromptStore
    private let settingsStore: SettingsStore
    private let promptUsageStore: PromptUsageStore
    private let openLibraryManager: () -> Void
    private let triggerModeChanged: () -> Void
    private let doubleControlTimingChanged: () -> Void
    private let openAccessibilitySettings: () -> Void
    private let requestAccessibilityPermission: () -> Void
    private let openInputMonitoringSettings: () -> Void
    private let requestInputMonitoringPermission: () -> Void
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
        promptUsageStore: PromptUsageStore,
        openLibraryManager: @escaping () -> Void = {},
        fallbackHotkeyStatusMessage: String? = nil,
        doubleControlStatus: DoubleControlTriggerStatus = .needsAccessibility,
        triggerModeChanged: @escaping () -> Void = {},
        doubleControlTimingChanged: @escaping () -> Void = {},
        openAccessibilitySettings: @escaping () -> Void = {},
        requestAccessibilityPermission: @escaping () -> Void = {},
        openInputMonitoringSettings: @escaping () -> Void = {},
        requestInputMonitoringPermission: @escaping () -> Void = {}
    ) {
        self.promptStore = promptStore
        self.settingsStore = settingsStore
        self.promptUsageStore = promptUsageStore
        self.openLibraryManager = openLibraryManager
        self.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        self.doubleControlStatus = doubleControlStatus
        self.triggerModeChanged = triggerModeChanged
        self.doubleControlTimingChanged = doubleControlTimingChanged
        self.openAccessibilitySettings = openAccessibilitySettings
        self.requestAccessibilityPermission = requestAccessibilityPermission
        self.openInputMonitoringSettings = openInputMonitoringSettings
        self.requestInputMonitoringPermission = requestInputMonitoringPermission
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
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
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
            promptUsageStore: promptUsageStore,
            openLibraryManager: openLibraryManager,
            fallbackHotkeyStatusMessage: fallbackHotkeyStatusMessage,
            doubleControlStatus: doubleControlStatus,
            triggerModeChanged: triggerModeChanged,
            doubleControlTimingChanged: doubleControlTimingChanged,
            openAccessibilitySettings: openAccessibilitySettings,
            requestAccessibilityPermission: requestAccessibilityPermission,
            openInputMonitoringSettings: openInputMonitoringSettings,
            requestInputMonitoringPermission: requestInputMonitoringPermission
        )
    }
}
