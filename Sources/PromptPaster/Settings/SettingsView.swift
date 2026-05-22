import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var promptStore: PromptStore
    let fallbackHotkeyStatusMessage: String?

    init(promptStore: PromptStore, fallbackHotkeyStatusMessage: String? = nil) {
        self.promptStore = promptStore
        self.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
    }

    var body: some View {
        Form {
            Section("Trigger") {
                LabeledContent("Primary trigger", value: "Double Control")
                LabeledContent("Fallback hotkey", value: HotkeyDisplay.fallbackShortcut)

                if let fallbackHotkeyStatusMessage {
                    Text(fallbackHotkeyStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
}
