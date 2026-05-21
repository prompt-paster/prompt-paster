import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let promptStore = PromptStore()
    private let overlayController = OverlayWindowController()
    private lazy var settingsController = SettingsWindowController(promptStore: promptStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        promptStore.load()
        configureStatusItem()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "text.bubble",
            accessibilityDescription: "Prompt Paster"
        )
        item.button?.imagePosition = .imageOnly
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: "Open Prompt Paster",
            action: #selector(openPromptPaster),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Open Prompt Library",
            action: #selector(openPromptLibrary),
            keyEquivalent: "o"
        )
        menu.addItem(
            withTitle: "Reload Library",
            action: #selector(reloadLibrary),
            keyEquivalent: "r"
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit Prompt Paster",
            action: #selector(quit),
            keyEquivalent: "q"
        )

        for item in menu.items {
            item.target = self
        }

        return menu
    }

    @objc private func openPromptPaster() {
        overlayController.show()
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func openPromptLibrary() {
        promptStore.openLibraryFile()
    }

    @objc private func reloadLibrary() {
        let result = promptStore.reload()
        if let errorMessage = result.errorMessage {
            overlayController.show(message: "Reload failed. Keeping last valid library. \(errorMessage)")
        } else {
            let promptCount = result.library?.prompts.count ?? 0
            overlayController.show(message: "Reloaded \(promptCount) prompts.")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
