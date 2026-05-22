import Foundation
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
    var isLaunchAtLoginEnabled: Bool { get }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws
}

struct LoginItemManager: LoginItemManaging {
    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let triggerMode = "settings.triggerMode"
        static let doubleControlThresholdMilliseconds = "settings.doubleControlThresholdMilliseconds"
        static let showCopiedConfirmation = "settings.showCopiedConfirmation"
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

    @Published var showCopiedConfirmation: Bool {
        didSet {
            defaults.set(showCopiedConfirmation, forKey: Keys.showCopiedConfirmation)
        }
    }

    @Published private(set) var launchAtLoginEnabled: Bool
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

        if defaults.object(forKey: Keys.showCopiedConfirmation) == nil {
            self.showCopiedConfirmation = true
        } else {
            self.showCopiedConfirmation = defaults.bool(forKey: Keys.showCopiedConfirmation)
        }

        self.launchAtLoginEnabled = loginItemManager.isLaunchAtLoginEnabled
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
        launchAtLoginEnabled = loginItemManager.isLaunchAtLoginEnabled
    }

    func setDoubleControlThresholdMilliseconds(_ threshold: Int) {
        doubleControlThresholdMilliseconds = Self.clampedThreshold(threshold)
        defaults.set(doubleControlThresholdMilliseconds, forKey: Keys.doubleControlThresholdMilliseconds)
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            try loginItemManager.setLaunchAtLoginEnabled(isEnabled)
            launchAtLoginEnabled = loginItemManager.isLaunchAtLoginEnabled
            launchAtLoginErrorMessage = nil
        } catch {
            launchAtLoginEnabled = loginItemManager.isLaunchAtLoginEnabled
            launchAtLoginErrorMessage = error.localizedDescription
        }
    }

    private static func clampedThreshold(_ threshold: Int) -> Int {
        min(
            maximumDoubleControlThresholdMilliseconds,
            max(minimumDoubleControlThresholdMilliseconds, threshold)
        )
    }
}
