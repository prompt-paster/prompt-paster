import AppKit
import SwiftUI

@MainActor
final class PromptLibraryManagerWindowController {
    private var window: NSWindow?
    private let promptStore: PromptStore

    init(promptStore: PromptStore) {
        self.promptStore = promptStore
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
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Prompt Library Editor"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PromptLibraryManagerView(
                viewModel: PromptLibraryManagerViewModel(promptStore: promptStore)
            )
        )
        return window
    }
}
