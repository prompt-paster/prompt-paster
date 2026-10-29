import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyTriggerHandling {
    private let launchAction: AppLaunchAction?

    init(launchAction: AppLaunchAction? = nil) {
        self.launchAction = launchAction
        super.init()
    }

    private var statusItem: NSStatusItem?
    private let promptStore = PromptStore()
    private let settingsStore = SettingsStore()
    private let promptUsageStore = PromptUsageStore()
    private let githubCredentialStore = GitHubCredentialStore()
    private var fallbackHotkeyStatusMessage: String?
    private var doubleControlStatus: DoubleControlTriggerStatus = .needsAccessibility
    private lazy var overlayController = OverlayWindowController(
        promptStore: promptStore,
        settingsStore: settingsStore,
        promptUsageStore: promptUsageStore,
        openSettings: { [weak self] in
            self?.openSettings()
        }
    )
    private lazy var settingsController = SettingsWindowController(
        promptStore: promptStore,
        settingsStore: settingsStore,
        promptUsageStore: promptUsageStore,
        githubCredentialStore: githubCredentialStore,
        openLibraryManager: { [weak self] in
            self?.openLibraryManager()
        },
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
        },
        openInputMonitoringSettings: { [weak self] in
            self?.hotkeyController.openInputMonitoringSettings()
        },
        requestInputMonitoringPermission: { [weak self] in
            self?.requestInputMonitoringPermission()
        }
    )
    private lazy var libraryManagerController = PromptLibraryManagerWindowController(promptStore: promptStore)
    private var hotkeyController: HotkeyController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenuBuilder.build(quitTarget: self, quitAction: #selector(quit))
        promptStore.load()
        prunePromptUsageStats()
        configureStatusItem()
        startHotkeys()
        switch launchAction {
        case .show: refreshSourcesAndShow()
        case .editLibrary: openLibraryManager()
        case .settings: openSettings()
        case nil: break
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { refreshSourcesAndShow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: StatusItemIcon.statusItemLength)
        if let button = item.button {
            button.image = nil
            button.imagePosition = .noImage
            button.title = StatusItemIcon.title
            button.toolTip = "Prompt Paster"
            button.setAccessibilityLabel(StatusItemIcon.accessibilityDescription)
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: "Open Prompt Paster (\(settingsStore.fallbackHotkeyDisplayName))",
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
            withTitle: "Edit Prompt Library...",
            action: #selector(openLibraryManager),
            keyEquivalent: "l"
        )
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
        if overlayController.isVisible {
            overlayController.hide()
        } else {
            refreshSourcesAndShow()
        }
    }

    @objc private func openPromptPaster() {
        refreshSourcesAndShow()
    }

    @objc private func openSettings() {
        settingsController.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        settingsController.doubleControlStatus = doubleControlStatus
        settingsController.refreshLaunchAtLoginStatus()
        settingsController.show()
    }

    @objc private func openLibraryManager() {
        libraryManagerController.show()
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
            prunePromptUsageStats()
            Task { [weak self] in
                guard let self else { return }
                await self.promptStore.refreshGitHubSources(token: self.githubCredentialStore.token)
                self.prunePromptUsageStats()
                self.overlayController.show(message: "Reloaded \(promptCount) local prompts and refreshed GitHub sources.")
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startHotkeys() {
        hotkeyController = HotkeyController(
            shortcut: settingsStore.fallbackHotkeyShortcut,
            triggerMode: settingsStore.triggerMode,
            doubleTapModifier: settingsStore.doubleTapModifier,
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
        statusItem?.menu = buildMenu()
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

    private func requestInputMonitoringPermission() {
        let status = hotkeyController.requestInputMonitoringPermission()
        applyHotkeyStatus(status)
        settingsController.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        settingsController.doubleControlStatus = doubleControlStatus
    }

    private func applyHotkeyStatus(_ status: HotkeyStartupStatus) {
        fallbackHotkeyStatusMessage = status.fallbackHotkeyStatusMessage
        doubleControlStatus = status.doubleControlStatus
    }

    private func prunePromptUsageStats() {
        let promptIDs = promptStore.library?.configuredPromptIDs ?? []
        promptUsageStore.pruneKeepingPromptIDs(promptIDs)
    }

    private func refreshSourcesAndShow() {
        settingsStore.reloadHomeConfiguration()
        Task { [weak self] in
            guard let self else { return }
            await self.promptStore.refreshGitHubSources(token: self.githubCredentialStore.token)
            self.prunePromptUsageStats()
            self.overlayController.show()
        }
    }
}
