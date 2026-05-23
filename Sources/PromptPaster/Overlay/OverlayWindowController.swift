import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private var panel: NSPanel?
    private var previouslyActiveApplication: NSRunningApplication?
    private let promptStore: PromptStore
    private let settingsStore: SettingsStore
    private let promptUsageStore: PromptUsageStore
    private let clipboard: ClipboardCopying
    private let openSettings: () -> Void

    init(
        promptStore: PromptStore,
        settingsStore: SettingsStore,
        promptUsageStore: PromptUsageStore,
        clipboard: ClipboardCopying = ClipboardService(),
        openSettings: @escaping () -> Void = {}
    ) {
        self.promptStore = promptStore
        self.settingsStore = settingsStore
        self.promptUsageStore = promptUsageStore
        self.clipboard = clipboard
        self.openSettings = openSettings
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show(message: String? = nil) {
        let panel = panel ?? makePanel()
        self.panel = panel
        previouslyActiveApplication = NSWorkspace.shared.frontmostApplication

        let activeScreen = screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = settingsStore.overlayDisplayConfiguration.size(for: visibleFrame)
        let frame = NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(
            rootView: PromptOverlayView(
                promptStore: promptStore,
                settingsStore: settingsStore,
                promptUsageStore: promptUsageStore,
                message: message,
                clipboard: clipboard,
                openSettings: { [weak self] in
                    self?.hide()
                    self?.openSettings()
                }
            ) { [weak self] in
                self?.hide()
            }
        )
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
        previouslyActiveApplication?.activate()
        previouslyActiveApplication = nil
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
