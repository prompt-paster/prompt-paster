import AppKit
import XCTest
@testable import PromptPaster

@MainActor
final class OverlayKeyboardIntegrationTests: XCTestCase {
    func testHomeLettersCopyTheirDisplayedFavoriteIncludingShiftAndNumericLibraryMode() throws {
        for (key, code, modifiers, expected) in [
            ("a", UInt16(0), NSEvent.ModifierFlags(), "datahack"),
            ("A", UInt16(0), .shift, "datahack"),
            ("s", UInt16(1), [], "adanim"),
            ("d", UInt16(2), [], "opeongo")
        ] {
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            fixture.settings.promptSelectionShortcutMode = .numbers
            fixture.controller.show()
            pumpEvents()
            let window = try XCTUnwrap(NSApp.keyWindow)
            XCTAssertTrue(window.isVisible)
            sendKey(key, code: code, modifiers: modifiers, window: window)
            XCTAssertEqual(fixture.clipboard.copiedTexts, ["Complete \(expected)\nSecond paragraph"], key)
            XCTAssertFalse(fixture.controller.isVisible, key)
        }
    }

    func testHomeCustomKeyAndReorderSelectTheDisplayedPrompt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.setHomePromptKey("z", for: "opeongo")
        fixture.settings.moveHomePrompt("opeongo", before: "datahack")
        fixture.controller.show()
        pumpEvents()
        sendKey("Z", code: 6, modifiers: .shift, window: try XCTUnwrap(NSApp.keyWindow))
        XCTAssertEqual(fixture.clipboard.copiedTexts, ["Complete opeongo\nSecond paragraph"])
        XCTAssertFalse(fixture.controller.isVisible)
    }

    func testHomeEnterAndArrowNavigationCannotSelectAHiddenLibraryPrompt() throws {
        for navigate in [false, true] {
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            fixture.controller.show()
            pumpEvents()
            let window = try XCTUnwrap(NSApp.keyWindow)
            if navigate { sendKey("", code: 124, modifiers: [], window: window) }
            sendKey("\r", code: 36, modifiers: [], window: window)
            let expected = navigate ? "adanim" : "datahack"
            XCTAssertEqual(fixture.clipboard.copiedTexts, ["Complete \(expected)\nSecond paragraph"])
            XCTAssertFalse(fixture.controller.isVisible)
        }
    }

    func testFocusedSearchAcceptsLettersAndNumericResultShortcutStillCopies() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.promptSelectionShortcutMode = .numbers
        fixture.controller.show()
        pumpEvents()
        let window = try XCTUnwrap(NSApp.keyWindow)
        let search = try XCTUnwrap(textFields(in: try XCTUnwrap(window.contentView)).first)
        XCTAssertTrue(window.makeFirstResponder(search))
        pumpEvents()
        for character in "adanim" { sendKey(String(character), code: 0, modifiers: [], window: window) }
        XCTAssertEqual(search.stringValue, "adanim")
        XCTAssertTrue(fixture.clipboard.copiedTexts.isEmpty)
        XCTAssertTrue(fixture.controller.isVisible)
        sendKey("1", code: 18, modifiers: [], window: window)
        XCTAssertEqual(fixture.clipboard.copiedTexts, ["Complete adanim\nSecond paragraph"])
        XCTAssertFalse(fixture.controller.isVisible)
    }

    func testEscapeClosesWithoutCopying() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.show()
        pumpEvents()
        sendKey("\u{1b}", code: 53, modifiers: [], window: try XCTUnwrap(NSApp.keyWindow))
        XCTAssertTrue(fixture.clipboard.copiedTexts.isEmpty)
        XCTAssertFalse(fixture.controller.isVisible)
    }

    func testHebrewLayoutHomeKeysStillCopyTheirLatinBadges() throws {
        for (character, code, expected) in [("ש", UInt16(0), "datahack"), ("ד", UInt16(1), "adanim"), ("ג", UInt16(2), "opeongo")] {
            let fixture = try Fixture()
            defer { fixture.cleanUp() }
            fixture.controller.show()
            pumpEvents()
            sendKey(character, code: code, modifiers: [], window: try XCTUnwrap(NSApp.keyWindow))
            XCTAssertEqual(fixture.clipboard.copiedTexts, ["Complete \(expected)\nSecond paragraph"])
            XCTAssertFalse(fixture.controller.isVisible)
        }
    }

    func testExplicitNonLatinShortcutHasPriorityOverPhysicalFallback() throws {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: 0, context: nil, characters: "ש", charactersIgnoringModifiers: "ש",
                                    isARepeat: false, keyCode: 0)!
        let assignments = [PromptOverlayShortcutAssignment(promptID: "latin", key: "a"),
                           PromptOverlayShortcutAssignment(promptID: "hebrew", key: "ש")]
        XCTAssertEqual(OverlayShortcutKey.promptID(for: event, assignments: assignments), "hebrew")
        XCTAssertEqual(OverlayShortcutKey.promptID(for: event, assignments: []), nil)
    }

    func testNinthHomeFavoriteCopiesWithHebrewPhysicalLAndKeepsPreviousEight() throws {
        let extra = (1...5).map { Prompt(id: "extra-\($0)", title: "Extra \($0)", body: "Extra body") }
            + [Prompt(id: "base-only", title: "Base only", body: "Base prompt without a suffix")]
        let fixture = try Fixture(additionalPrompts: extra)
        defer { fixture.cleanUp() }
        for index in 1...5 { fixture.settings.toggleFavorite(promptID: "extra-\(index)") }
        let oldSlots = fixture.settings.homePromptSlots
        XCTAssertEqual(oldSlots.count, 8)
        fixture.settings.toggleFavorite(promptID: "base-only")
        XCTAssertEqual(Array(fixture.settings.homePromptSlots.prefix(8)), oldSlots)
        XCTAssertEqual(fixture.settings.homePromptSlots.last?.key, "l")
        fixture.controller.show()
        pumpEvents()
        sendKey("ך", code: 37, modifiers: [], window: try XCTUnwrap(NSApp.keyWindow))
        XCTAssertEqual(fixture.clipboard.copiedTexts, ["Base prompt without a suffix"])
        XCTAssertFalse(fixture.controller.isVisible)
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    private func sendKey(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags, window: NSWindow) {
        window.makeKey()
        XCTAssertTrue(window.isKeyWindow)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, characters: characters, charactersIgnoringModifiers: characters.lowercased(),
                                    isARepeat: false, keyCode: code)!
        NSApp.postEvent(event, atStart: false)
        pumpEvents()
    }

    private func pumpEvents() {
        let deadline = Date().addingTimeInterval(0.12)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        } while Date() < deadline
    }
}

@MainActor
private final class Fixture {
    let folder: URL
    let suite: String
    let settings: SettingsStore
    let clipboard = KeyboardTestClipboard()
    let controller: OverlayWindowController

    init(additionalPrompts: [Prompt] = []) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("PromptPasterKeyboard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "PromptPasterKeyboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        settings = SettingsStore(defaults: defaults, loginItemManager: KeyboardTestLoginManager())
        let prompts = [Prompt(id: "hidden", title: "Not on home", body: "Do not copy the hidden local prompt")] +
            ["datahack", "adanim", "opeongo"].map { Prompt(id: $0, title: $0.capitalized, body: "Complete \($0)\nSecond paragraph") } + additionalPrompts
        let seed = folder.appendingPathComponent("seed.json")
        try PromptLibraryCoding.makeEncoder().encode(PromptLibrary(prompts: prompts)).write(to: seed)
        let store = PromptStore(applicationSupportURL: folder.appendingPathComponent("Support"), seedURL: seed)
        _ = store.load()
        for id in ["datahack", "adanim", "opeongo"] { settings.toggleFavorite(promptID: id) }
        let usage = PromptUsageStore(defaults: defaults)
        controller = OverlayWindowController(promptStore: store, settingsStore: settings, promptUsageStore: usage, clipboard: clipboard)
    }

    func cleanUp() {
        controller.hide()
        for window in NSApp.windows where window is NSPanel { window.close() }
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
}

@MainActor
private final class KeyboardTestClipboard: ClipboardCopying {
    var copiedTexts: [String] = []
    func copyPlainText(_ text: String) throws { copiedTexts.append(text) }
}

private struct KeyboardTestLoginManager: LoginItemManaging {
    var launchAtLoginStatus: LaunchAtLoginStatus { .disabled }
    func setLaunchAtLoginEnabled(_ enabled: Bool) throws {}
    func openLoginItemsSettings() {}
}
