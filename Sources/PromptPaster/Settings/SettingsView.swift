import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var promptStore: PromptStore
    let fallbackHotkeyStatusMessage: String?
    let doubleControlStatusMessage: String?
    let isDoubleControlActive: Bool
    let openAccessibilitySettings: () -> Void

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

    var body: some View {
        Form {
            Section("Trigger") {
                LabeledContent("Fallback hotkey", value: HotkeyDisplay.fallbackShortcut)
                LabeledContent(
                    HotkeyDisplay.doubleControlShortcut,
                    value: doubleControlStatusValue
                )
                LabeledContent("Double Control timing", value: HotkeyDisplay.doubleControlThreshold)

                if let fallbackHotkeyStatusMessage {
                    Text(fallbackHotkeyStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let doubleControlStatusMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(doubleControlStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)

                        Button("Open Accessibility Settings") {
                            openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("Prompt Library") {
                LabeledContent("Storage", value: promptStore.libraryURL.path)
                LabeledContent("Loaded prompts", value: "\(promptStore.library?.prompts.count ?? 0)")

                if let lastErrorMessage = promptStore.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("Open Prompt Library") {
                        do {
                            let libraryURL = try promptStore.prepareLibraryFile()
                            NSWorkspace.shared.open(libraryURL)
                        } catch {
                            promptStore.recordError(error)
                        }
                    }

                    Button("Reload Library") {
                        promptStore.reload()
                    }
                }
            }

            Section("App") {
                LabeledContent("Launch at login", value: "Planned")
                LabeledContent("Dock icon", value: "Hidden")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }

    private var doubleControlStatusValue: String {
        if isDoubleControlActive {
            return "Active"
        }
        if doubleControlStatusMessage?.contains("Accessibility") == true {
            return "Needs Accessibility"
        }
        return "Unavailable"
    }
}
