import SwiftUI

struct SettingsView: View {
    @ObservedObject var promptStore: PromptStore

    var body: some View {
        Form {
            Section("Trigger") {
                LabeledContent("Primary trigger", value: "Double Control")
                LabeledContent("Fallback hotkey", value: "Control + Option + Space")
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
                        promptStore.openLibraryFile()
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
