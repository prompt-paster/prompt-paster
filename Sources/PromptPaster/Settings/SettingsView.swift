import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Trigger") {
                LabeledContent("Primary trigger", value: "Double Control")
                LabeledContent("Fallback hotkey", value: "Control + Option + Space")
            }

            Section("Prompt Library") {
                LabeledContent("Storage", value: "Planned for PROMPTS-1")
                LabeledContent("Reload", value: "Available after storage lands")
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
