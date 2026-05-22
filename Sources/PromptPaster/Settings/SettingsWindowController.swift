import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let promptStore: PromptStore
    var fallbackHotkeyStatusMessage: String? {
        didSet {
            window?.contentView = NSHostingView(
                rootView: SettingsView(
                    promptStore: promptStore,
                    fallbackHotkeyStatusMessage: fallbackHotkeyStatusMessage
                )
            )
        }
    }

    init(promptStore: PromptStore, fallbackHotkeyStatusMessage: String? = nil) {
        self.promptStore = promptStore
        self.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
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
        window.contentView = NSHostingView(
            rootView: SettingsView(
                promptStore: promptStore,
                fallbackHotkeyStatusMessage: fallbackHotkeyStatusMessage
            )
        )
        return window
    }
}
