import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var promptStore: PromptStore
    @ObservedObject var settingsStore: SettingsStore
    let fallbackHotkeyStatusMessage: String?
    let doubleControlStatus: DoubleControlTriggerStatus
    let triggerModeChanged: () -> Void
    let doubleControlTimingChanged: () -> Void
    let openAccessibilitySettings: () -> Void
    let requestAccessibilityPermission: () -> Void

    init(
        promptStore: PromptStore,
        settingsStore: SettingsStore,
        fallbackHotkeyStatusMessage: String? = nil,
        doubleControlStatus: DoubleControlTriggerStatus = .needsAccessibility,
        triggerModeChanged: @escaping () -> Void = {},
        doubleControlTimingChanged: @escaping () -> Void = {},
        openAccessibilitySettings: @escaping () -> Void = {},
        requestAccessibilityPermission: @escaping () -> Void = {}
    ) {
        self.promptStore = promptStore
        self.settingsStore = settingsStore
        self.fallbackHotkeyStatusMessage = fallbackHotkeyStatusMessage
        self.doubleControlStatus = doubleControlStatus
        self.triggerModeChanged = triggerModeChanged
        self.doubleControlTimingChanged = doubleControlTimingChanged
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
                triggerModeChanged()
            }
            .onChange(of: settingsStore.doubleControlThresholdMilliseconds) { _, _ in
                doubleControlTimingChanged()
            }

            Section("Overlay Display") {
                Picker("Overlay size", selection: $settingsStore.overlaySizeMode) {
                    ForEach(OverlaySizeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if settingsStore.overlaySizeMode == .percentageOfDisplay {
                    Stepper(
                        "Display size: \(settingsStore.overlayDisplayPercentageDisplayValue)",
                        value: Binding(
                            get: {
                                settingsStore.overlayDisplayPercentage
                            },
                            set: { percentage in
                                settingsStore.setOverlayDisplayPercentage(percentage)
                            }
                        ),
                        in: SettingsStore.minimumOverlayDisplayPercentage...SettingsStore.maximumOverlayDisplayPercentage,
                        step: 5
                    )
                } else {
                    HStack {
                        Text("Fixed size")
                        Spacer()
                        PixelField(
                            title: "Width",
                            value: Binding(
                                get: {
                                    settingsStore.overlayFixedWidthPixels
                                },
                                set: { width in
                                    settingsStore.setOverlayFixedWidthPixels(width)
                                }
                            )
                        )
                        Text("x")
                            .foregroundStyle(.secondary)
                        PixelField(
                            title: "Height",
                            value: Binding(
                                get: {
                                    settingsStore.overlayFixedHeightPixels
                                },
                                set: { height in
                                    settingsStore.setOverlayFixedHeightPixels(height)
                                }
                            )
                        )
                        Text("px")
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(
                    "Prompt preview: \(settingsStore.promptPreviewCharacterLimitDisplayValue)",
                    value: Binding(
                        get: {
                            settingsStore.promptPreviewCharacterLimit
                        },
                        set: { characterLimit in
                            settingsStore.setPromptPreviewCharacterLimit(characterLimit)
                        }
                    ),
                    in: SettingsStore.minimumPromptPreviewCharacterLimit...SettingsStore.maximumPromptPreviewCharacterLimit,
                    step: 20
                )

                Picker("Selection shortcuts", selection: $settingsStore.promptSelectionShortcutMode) {
                    ForEach(PromptSelectionShortcutMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
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

                    Button("Reveal in Finder") {
                        do {
                            let libraryURL = try promptStore.prepareLibraryFile()
                            NSWorkspace.shared.activateFileViewerSelecting([libraryURL])
                        } catch {
                            promptStore.recordError(error)
                        }
                    }
                }
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: {
                        settingsStore.launchAtLoginStatus.isToggleOn
                    },
                    set: { isEnabled in
                        settingsStore.setLaunchAtLoginEnabled(isEnabled)
                    }
                ))
                LabeledContent("Launch at login status", value: settingsStore.launchAtLoginStatus.displayValue)
                LabeledContent("Dock icon", value: "Hidden")

                if settingsStore.launchAtLoginStatus == .requiresApproval {
                    Button("Open Login Items Settings") {
                        settingsStore.openLoginItemsSettings()
                    }
                }

                if let launchAtLoginStatusMessage = settingsStore.launchAtLoginStatus.message {
                    Text(launchAtLoginStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if let launchAtLoginErrorMessage = settingsStore.launchAtLoginErrorMessage {
                    Text(launchAtLoginErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 540, minHeight: 560)
    }
}

private struct PixelField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        TextField(title, value: $value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 76)
            .multilineTextAlignment(.trailing)
    }
}
