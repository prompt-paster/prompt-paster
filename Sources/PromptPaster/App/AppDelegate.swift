import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyTriggerHandling {
    private var statusItem: NSStatusItem?
    private let promptStore = PromptStore()
    private let settingsStore = SettingsStore()
    private var fallbackHotkeyStatusMessage: String?
    private var doubleControlStatus: DoubleControlTriggerStatus = .needsAccessibility
    private lazy var overlayController = OverlayWindowController(
        promptStore: promptStore,
        openSettings: { [weak self] in
            self?.openSettings()
        }
    )
    private lazy var settingsController = SettingsWindowController(
        promptStore: promptStore,
        settingsStore: settingsStore,
        fallbackHotkeyStatusMessage: fallbackHotkeyStatusMessage,
        doubleControlStatus: doubleControlStatus,
        triggerModeChanged: { [weak self] in
            self?.restartHotkeys()
        },
        doubleControlTimingChanged: { [weak self] in
            self?.updateDoubleControlTiming()
        },
        openAccessibilitySettings: { [weak self] in
            self?.hotkeyController.openAccessibilitySettings()
        },
        requestAccessibilityPermission: { [weak self] in
            self?.requestAccessibilityPermission()
        }
    )
    private var hotkeyController: HotkeyController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenuBuilder.build(quitTarget: self, quitAction: #selector(quit))
        promptStore.load()
        configureStatusItem()
        startHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = StatusItemIcon.makeMenuBarImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Prompt Paster"
            button.setAccessibilityLabel(StatusItemIcon.accessibilityDescription)
            button.title = ""
        }
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
        settingsController.doubleControlStatus = doubleControlStatus
        settingsController.refreshLaunchAtLoginStatus()
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

    private func startHotkeys() {
        hotkeyController = HotkeyController(
            triggerMode: settingsStore.triggerMode,
            handler: self,
            doubleControlConfiguration: settingsStore.doubleControlConfiguration
        )

        do {
            let status = try hotkeyController.start()
            applyHotkeyStatus(status)
        } catch {
            fallbackHotkeyStatusMessage = "Fallback hotkey unavailable. \(error.localizedDescription)"
            doubleControlStatus = .monitorUnavailable("Double Control not started because fallback hotkey registration failed.")
            NSLog("Prompt Paster fallback hotkey unavailable: \(error.localizedDescription)")
        }
    }

    private func restartHotkeys() {
        hotkeyController?.stop()
        startHotkeys()
        settingsController.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        settingsController.doubleControlStatus = doubleControlStatus
    }

    private func updateDoubleControlTiming() {
        hotkeyController?.updateDoubleControlConfiguration(settingsStore.doubleControlConfiguration)
    }

    private func requestAccessibilityPermission() {
        let status = hotkeyController.requestAccessibilityPermission()
        applyHotkeyStatus(status)
        settingsController.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        settingsController.doubleControlStatus = doubleControlStatus
    }

    private func applyHotkeyStatus(_ status: HotkeyStartupStatus) {
        fallbackHotkeyStatusMessage = status.fallbackHotkeyStatusMessage
        doubleControlStatus = status.doubleControlStatus
    }
}
