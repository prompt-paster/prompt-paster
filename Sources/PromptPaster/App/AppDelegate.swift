import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyTriggerHandling {
    private var statusItem: NSStatusItem?
    private let promptStore = PromptStore()
    private var fallbackHotkeyStatusMessage: String?
    private var doubleControlStatusMessage: String?
    private var isDoubleControlActive = false
    private lazy var overlayController = OverlayWindowController(promptStore: promptStore)
    private lazy var settingsController = SettingsWindowController(
        promptStore: promptStore,
        fallbackHotkeyStatusMessage: fallbackHotkeyStatusMessage,
        doubleControlStatusMessage: doubleControlStatusMessage,
        isDoubleControlActive: isDoubleControlActive,
        openAccessibilitySettings: { [weak self] in
            self?.hotkeyController.openAccessibilitySettings()
        }
    )
    private lazy var hotkeyController = HotkeyController(handler: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        promptStore.load()
        configureStatusItem()
        startFallbackHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController.stop()
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
            withTitle: "Open Prompt Paster (\(HotkeyDisplay.fallbackShortcut))",
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

    func handleHotkeyTrigger() {
        overlayController.toggle()
    }

    @objc private func openPromptPaster() {
        overlayController.show()
    }

    @objc private func openSettings() {
        settingsController.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        settingsController.doubleControlStatusMessage = doubleControlStatusMessage
        settingsController.isDoubleControlActive = isDoubleControlActive
        settingsController.show()
    }

    @objc private func openPromptLibrary() {
        do {
            let libraryURL = try promptStore.prepareLibraryFile()
            NSWorkspace.shared.open(libraryURL)
        } catch {
            promptStore.recordError(error)
            overlayController.show(message: "Could not open prompt library. \(error.localizedDescription)")
        }
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

    private func startFallbackHotkey() {
        do {
            let status = try hotkeyController.start()
            fallbackHotkeyStatusMessage = status.fallbackHotkeyStatusMessage
            doubleControlStatusMessage = status.doubleControlStatusMessage
            isDoubleControlActive = status.isDoubleControlActive
        } catch {
            fallbackHotkeyStatusMessage = "Fallback hotkey unavailable. \(error.localizedDescription)"
            doubleControlStatusMessage = "Double Control not started because fallback hotkey registration failed."
            isDoubleControlActive = false
            NSLog("Prompt Paster fallback hotkey unavailable: \(error.localizedDescription)")
        }
    }
}
