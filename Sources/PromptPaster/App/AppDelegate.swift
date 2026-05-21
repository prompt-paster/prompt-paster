import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let overlayController = OverlayWindowController()
    private let settingsController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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

    @objc private func reloadLibrary() {
        overlayController.show(message: "Prompt library reloading lands in PROMPTS-1.")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
