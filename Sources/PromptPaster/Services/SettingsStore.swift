import Foundation
import AppKit
import ServiceManagement

enum TriggerMode: String, CaseIterable, Identifiable {
    case doubleControlWithFallback
    case fallbackHotkeyOnly

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .doubleControlWithFallback:
            "Double Control + fallback hotkey"
        case .fallbackHotkeyOnly:
            "Fallback hotkey only"
        }
    }
}

protocol LoginItemManaging {
    var launchAtLoginStatus: LaunchAtLoginStatus { get }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws
    func openLoginItemsSettings()
}

struct LoginItemManager: LoginItemManaging {
    var launchAtLoginStatus: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered:
            .disabled
        case .notFound:
            .unavailable("Login item registration is unavailable for this app bundle.")
        @unknown default:
            .unavailable("Login item status is unavailable on this macOS version.")
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let triggerMode = "settings.triggerMode"
        static let doubleControlThresholdMilliseconds = "settings.doubleControlThresholdMilliseconds"
    }

    static let defaultDoubleControlThresholdMilliseconds = 350
    static let minimumDoubleControlThresholdMilliseconds = 250
    static let maximumDoubleControlThresholdMilliseconds = 700

    @Published var triggerMode: TriggerMode {
        didSet {
            defaults.set(triggerMode.rawValue, forKey: Keys.triggerMode)
        }
    }

    @Published private(set) var doubleControlThresholdMilliseconds: Int

    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published private(set) var launchAtLoginErrorMessage: String?

    private let defaults: UserDefaults
    private let loginItemManager: LoginItemManaging

    init(
        defaults: UserDefaults = .standard,
        loginItemManager: LoginItemManaging = LoginItemManager()
    ) {
        self.defaults = defaults
        self.loginItemManager = loginItemManager

        if let rawTriggerMode = defaults.string(forKey: Keys.triggerMode),
           let triggerMode = TriggerMode(rawValue: rawTriggerMode) {
            self.triggerMode = triggerMode
        } else {
            self.triggerMode = .doubleControlWithFallback
        }

        let storedThreshold = defaults.integer(forKey: Keys.doubleControlThresholdMilliseconds)
        if storedThreshold == 0 {
            self.doubleControlThresholdMilliseconds = Self.defaultDoubleControlThresholdMilliseconds
        } else {
            self.doubleControlThresholdMilliseconds = Self.clampedThreshold(storedThreshold)
        }

        self.launchAtLoginStatus = loginItemManager.launchAtLoginStatus
        self.launchAtLoginErrorMessage = nil
    }

    var doubleControlConfiguration: DoubleControlTapConfiguration {
        DoubleControlTapConfiguration(
            tapThreshold: TimeInterval(doubleControlThresholdMilliseconds) / 1_000,
            debounceInterval: DoubleControlTapConfiguration.default.debounceInterval
        )
    }

    var doubleControlThresholdDisplayValue: String {
        "\(doubleControlThresholdMilliseconds) ms"
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = loginItemManager.launchAtLoginStatus
    }

    func setDoubleControlThresholdMilliseconds(_ threshold: Int) {
        doubleControlThresholdMilliseconds = Self.clampedThreshold(threshold)
        defaults.set(doubleControlThresholdMilliseconds, forKey: Keys.doubleControlThresholdMilliseconds)
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try loginItemManager.setLaunchAtLoginEnabled(isEnabled)
            launchAtLoginStatus = loginItemManager.launchAtLoginStatus
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginStatus = loginItemManager.launchAtLoginStatus
            launchAtLoginErrorMessage = error.localizedDescription
        }
    }

    func openLoginItemsSettings() {
        loginItemManager.openLoginItemsSettings()
    }

    private static func clampedThreshold(_ threshold: Int) -> Int {
        min(
            maximumDoubleControlThresholdMilliseconds,
            max(minimumDoubleControlThresholdMilliseconds, threshold)
        )
    }
}

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable(String)

    var isToggleOn: Bool {
        switch self {
        case .enabled, .requiresApproval:
            true
        case .disabled, .unavailable:
            false
        }
    }

    var displayValue: String {
        switch self {
        case .enabled:
            "Enabled"
        case .disabled:
            "Disabled"
        case .requiresApproval:
            "Requires approval"
        case .unavailable:
            "Unavailable"
        }
    }

    var message: String? {
        switch self {
        case .enabled, .disabled:
            nil
        case .requiresApproval:
            "Launch at login is registered but needs approval in System Settings."
        case let .unavailable(message):
            message
        }
    }
}
