import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let promptStore: PromptStore
    private let openAccessibilitySettings: () -> Void
    var fallbackHotkeyStatusMessage: String? {
        didSet {
            refreshContentView()
        }
    }
    var doubleControlStatusMessage: String? {
        didSet {
            refreshContentView()
        }
    }
    var isDoubleControlActive: Bool {
        didSet {
            refreshContentView()
        }
    }

    init(
        promptStore: PromptStore,
        fallbackHotkeyStatusMessage: String? = nil,
        doubleControlStatusMessage: String? = nil,
        isDoubleControlActive: Bool = false,
        openAccessibilitySettings: @escaping () -> Void = {}
    ) {
        self.promptStore = promptStore
        self.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        self.doubleControlStatusMessage = doubleControlStatusMessage
        self.isDoubleControlActive = isDoubleControlActive
        self.openAccessibilitySettings = openAccessibilitySettings
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
            fallbackHotkeyStatusMessage: fallbackHotkeyStatusMessage,
            doubleControlStatusMessage: doubleControlStatusMessage,
            isDoubleControlActive: isDoubleControlActive,
            openAccessibilitySettings: openAccessibilitySettings
        )
    }
}
