import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var promptStore: PromptStore
    @ObservedObject var settingsStore: SettingsStore
    let fallbackHotkeyStatusMessage: String?
    let doubleControlStatus: DoubleControlTriggerStatus
    let settingsChanged: () -> Void
    let openAccessibilitySettings: () -> Void
    let requestAccessibilityPermission: () -> Void

    init(
        promptStore: PromptStore,
        settingsStore: SettingsStore,
        fallbackHotkeyStatusMessage: String? = nil,
        doubleControlStatus: DoubleControlTriggerStatus = .needsAccessibility,
        settingsChanged: @escaping () -> Void = {},
        openAccessibilitySettings: @escaping () -> Void = {},
        requestAccessibilityPermission: @escaping () -> Void = {}
    ) {
        self.promptStore = promptStore
        self.settingsStore = settingsStore
        self.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        self.doubleControlStatus = doubleControlStatus
        self.settingsChanged = settingsChanged
        self.openAccessibilitySettings = openAccessibilitySettings
        self.requestAccessibilityPermission = requestAccessibilityPermission
    }

    var body: some View {
        Form {
            Section("Trigger") {
                Picker("Primary trigger", selection: $settingsStore.triggerMode) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                LabeledContent("Fallback hotkey", value: HotkeyDisplay.fallbackShortcut)
                LabeledContent(
                    HotkeyDisplay.doubleControlShortcut,
                    value: doubleControlStatus.displayValue
                )
                Stepper(
                    "Double Control timing: \(settingsStore.doubleControlThresholdDisplayValue)",
                    value: Binding(
                        get: {
                            settingsStore.doubleControlThresholdMilliseconds
                        },
                        set: { threshold in
                            settingsStore.setDoubleControlThresholdMilliseconds(threshold)
                        }
                    ),
                    in: SettingsStore.minimumDoubleControlThresholdMilliseconds...SettingsStore.maximumDoubleControlThresholdMilliseconds,
                    step: 25
                )

                if let fallbackHotkeyStatusMessage {
                    Text(fallbackHotkeyStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let doubleControlStatusMessage = doubleControlStatus.message {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(doubleControlStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)

                        if doubleControlStatus.canRequestAccessibilityPermission {
                            HStack {
                                Button("Request Accessibility Permission") {
                                    requestAccessibilityPermission()
                                }

                                Button("Open Accessibility Settings") {
                                    openAccessibilitySettings()
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: settingsStore.triggerMode) { _, _ in
                settingsChanged()
            }
            .onChange(of: settingsStore.doubleControlThresholdMilliseconds) { _, _ in
                settingsChanged()
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

                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([promptStore.libraryURL])
                    }
                }
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: {
                        settingsStore.launchAtLoginEnabled
                    },
                    set: { isEnabled in
                        settingsStore.setLaunchAtLoginEnabled(isEnabled)
                    }
                ))
                Toggle("Show copied confirmation", isOn: $settingsStore.showCopiedConfirmation)
                LabeledContent("Dock icon", value: "Hidden")

                if let launchAtLoginErrorMessage = settingsStore.launchAtLoginErrorMessage {
                    Text(launchAtLoginErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }
}
