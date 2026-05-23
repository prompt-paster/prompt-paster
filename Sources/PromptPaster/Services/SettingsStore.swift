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

enum PromptSelectionShortcutMode: String, CaseIterable, Identifiable {
    case spatialLetters
    case numbers

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .spatialLetters:
            "Spatial letters"
        case .numbers:
            "Numbers 1-9"
        }
    }
}

enum PromptOrderingMode: String, CaseIterable, Identifiable {
    case libraryOrder
    case mostUsed
    case recentlyUsed

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .libraryOrder:
            "Library order"
        case .mostUsed:
            "Most used"
        case .recentlyUsed:
            "Recently used"
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
        static let overlaySizeMode = "settings.overlaySizeMode"
        static let overlayDisplayPercentage = "settings.overlayDisplayPercentage"
        static let overlayFixedWidthPixels = "settings.overlayFixedWidthPixels"
        static let overlayFixedHeightPixels = "settings.overlayFixedHeightPixels"
        static let promptPreviewCharacterLimit = "settings.promptPreviewCharacterLimit"
        static let promptSelectionShortcutMode = "settings.promptSelectionShortcutMode"
        static let promptOrderingMode = "settings.promptOrderingMode"
        static let promptOrderingOverridesByCategoryID = "settings.promptOrderingOverridesByCategoryID"
    }

    nonisolated static let defaultDoubleControlThresholdMilliseconds = 350
    nonisolated static let minimumDoubleControlThresholdMilliseconds = 250
    nonisolated static let maximumDoubleControlThresholdMilliseconds = 700
    nonisolated static let defaultOverlayDisplayPercentage = OverlayDisplayConfiguration.defaultDisplayPercentage
    nonisolated static let minimumOverlayDisplayPercentage = OverlayDisplayConfiguration.minimumDisplayPercentage
    nonisolated static let maximumOverlayDisplayPercentage = OverlayDisplayConfiguration.maximumDisplayPercentage
    nonisolated static let defaultOverlayFixedWidthPixels = OverlayDisplayConfiguration.defaultFixedWidthPixels
    nonisolated static let defaultOverlayFixedHeightPixels = OverlayDisplayConfiguration.defaultFixedHeightPixels
    nonisolated static let minimumOverlayWidthPixels = OverlayDisplayConfiguration.minimumFixedModeWidthPixels
    nonisolated static let maximumOverlayWidthPixels = OverlayDisplayConfiguration.maximumFixedModeWidthPixels
    nonisolated static let minimumOverlayHeightPixels = OverlayDisplayConfiguration.minimumFixedModeHeightPixels
    nonisolated static let maximumOverlayHeightPixels = OverlayDisplayConfiguration.maximumFixedModeHeightPixels
    nonisolated static let defaultPromptPreviewCharacterLimit = 260
    nonisolated static let minimumPromptPreviewCharacterLimit = 40
    nonisolated static let maximumPromptPreviewCharacterLimit = 600

    @Published var triggerMode: TriggerMode {
        didSet {
            defaults.set(triggerMode.rawValue, forKey: Keys.triggerMode)
        }
    }

    @Published private(set) var doubleControlThresholdMilliseconds: Int
    @Published var overlaySizeMode: OverlaySizeMode {
        didSet {
            defaults.set(overlaySizeMode.rawValue, forKey: Keys.overlaySizeMode)
        }
    }
    @Published private(set) var overlayDisplayPercentage: Int
    @Published private(set) var overlayFixedWidthPixels: Int
    @Published private(set) var overlayFixedHeightPixels: Int
    @Published private(set) var promptPreviewCharacterLimit: Int
    @Published var promptSelectionShortcutMode: PromptSelectionShortcutMode {
        didSet {
            defaults.set(promptSelectionShortcutMode.rawValue, forKey: Keys.promptSelectionShortcutMode)
        }
    }
    @Published var promptOrderingMode: PromptOrderingMode {
        didSet {
            defaults.set(promptOrderingMode.rawValue, forKey: Keys.promptOrderingMode)
        }
    }
    @Published private(set) var promptOrderingOverridesByCategoryID: [String: PromptOrderingMode]

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

        if let rawOverlaySizeMode = defaults.string(forKey: Keys.overlaySizeMode),
           let overlaySizeMode = OverlaySizeMode(rawValue: rawOverlaySizeMode) {
            self.overlaySizeMode = overlaySizeMode
        } else {
            self.overlaySizeMode = .percentageOfDisplay
        }
        self.overlayDisplayPercentage = Self.clampedOverlayDisplayPercentage(
            Self.storedInt(
                defaults,
                key: Keys.overlayDisplayPercentage,
                defaultValue: Self.defaultOverlayDisplayPercentage
            )
        )
        self.overlayFixedWidthPixels = Self.clampedOverlayFixedWidthPixels(
            Self.storedInt(
                defaults,
                key: Keys.overlayFixedWidthPixels,
                defaultValue: Self.defaultOverlayFixedWidthPixels
            )
        )
        self.overlayFixedHeightPixels = Self.clampedOverlayFixedHeightPixels(
            Self.storedInt(
                defaults,
                key: Keys.overlayFixedHeightPixels,
                defaultValue: Self.defaultOverlayFixedHeightPixels
            )
        )
        self.promptPreviewCharacterLimit = Self.clampedPromptPreviewCharacterLimit(
            Self.storedInt(
                defaults,
                key: Keys.promptPreviewCharacterLimit,
                defaultValue: Self.defaultPromptPreviewCharacterLimit
            )
        )
        if let rawShortcutMode = defaults.string(forKey: Keys.promptSelectionShortcutMode),
           let shortcutMode = PromptSelectionShortcutMode(rawValue: rawShortcutMode) {
            self.promptSelectionShortcutMode = shortcutMode
        } else {
            self.promptSelectionShortcutMode = .spatialLetters
        }
        if let rawOrderingMode = defaults.string(forKey: Keys.promptOrderingMode),
           let orderingMode = PromptOrderingMode(rawValue: rawOrderingMode) {
            self.promptOrderingMode = orderingMode
        } else {
            self.promptOrderingMode = .libraryOrder
        }
        self.promptOrderingOverridesByCategoryID = Self.loadOrderingOverrides(
            from: defaults,
            key: Keys.promptOrderingOverridesByCategoryID
        )

        self.launchAtLoginStatus = loginItemManager.launchAtLoginStatus
        self.launchAtLoginErrorMessage = nil
    }

    var overlayDisplayConfiguration: OverlayDisplayConfiguration {
        OverlayDisplayConfiguration(
            sizeMode: overlaySizeMode,
            displayPercentage: overlayDisplayPercentage,
            fixedWidth: overlayFixedWidthPixels,
            fixedHeight: overlayFixedHeightPixels
        )
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

    var overlayDisplayPercentageDisplayValue: String {
        "\(overlayDisplayPercentage)%"
    }

    var overlayFixedSizeDisplayValue: String {
        "\(overlayFixedWidthPixels) x \(overlayFixedHeightPixels) px"
    }

    var promptPreviewCharacterLimitDisplayValue: String {
        "\(promptPreviewCharacterLimit) characters"
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = loginItemManager.launchAtLoginStatus
    }

    func setDoubleControlThresholdMilliseconds(_ threshold: Int) {
        doubleControlThresholdMilliseconds = Self.clampedThreshold(threshold)
        defaults.set(doubleControlThresholdMilliseconds, forKey: Keys.doubleControlThresholdMilliseconds)
    }

    func setOverlayDisplayPercentage(_ percentage: Int) {
        overlayDisplayPercentage = Self.clampedOverlayDisplayPercentage(percentage)
        defaults.set(overlayDisplayPercentage, forKey: Keys.overlayDisplayPercentage)
    }

    func setOverlayFixedWidthPixels(_ width: Int) {
        overlayFixedWidthPixels = Self.clampedOverlayFixedWidthPixels(width)
        defaults.set(overlayFixedWidthPixels, forKey: Keys.overlayFixedWidthPixels)
    }

    func setOverlayFixedHeightPixels(_ height: Int) {
        overlayFixedHeightPixels = Self.clampedOverlayFixedHeightPixels(height)
        defaults.set(overlayFixedHeightPixels, forKey: Keys.overlayFixedHeightPixels)
    }

    func setPromptPreviewCharacterLimit(_ characterLimit: Int) {
        promptPreviewCharacterLimit = Self.clampedPromptPreviewCharacterLimit(characterLimit)
        defaults.set(promptPreviewCharacterLimit, forKey: Keys.promptPreviewCharacterLimit)
    }

    func promptOrderingMode(for categoryID: String) -> PromptOrderingMode {
        guard categoryID != PromptCategoryFilter.all.id else {
            return promptOrderingMode
        }

        return promptOrderingOverridesByCategoryID[categoryID] ?? promptOrderingMode
    }

    func promptOrderingOverride(for categoryID: String) -> PromptOrderingMode? {
        promptOrderingOverridesByCategoryID[categoryID]
    }

    func setPromptOrderingOverride(_ override: PromptOrderingMode?, for categoryID: String) {
        guard categoryID != PromptCategoryFilter.all.id else {
            return
        }

        if let override {
            promptOrderingOverridesByCategoryID[categoryID] = override
        } else {
            promptOrderingOverridesByCategoryID.removeValue(forKey: categoryID)
        }
        persistPromptOrderingOverrides()
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

    private static func clampedOverlayDisplayPercentage(_ percentage: Int) -> Int {
        min(maximumOverlayDisplayPercentage, max(minimumOverlayDisplayPercentage, percentage))
    }

    private static func clampedOverlayFixedWidthPixels(_ width: Int) -> Int {
        min(maximumOverlayWidthPixels, max(minimumOverlayWidthPixels, width))
    }

    private static func clampedOverlayFixedHeightPixels(_ height: Int) -> Int {
        min(maximumOverlayHeightPixels, max(minimumOverlayHeightPixels, height))
    }

    private static func clampedPromptPreviewCharacterLimit(_ characterLimit: Int) -> Int {
        min(
            maximumPromptPreviewCharacterLimit,
            max(minimumPromptPreviewCharacterLimit, characterLimit)
        )
    }

    private static func storedInt(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Int
    ) -> Int {
        let storedValue = defaults.integer(forKey: key)
        return storedValue == 0 ? defaultValue : storedValue
    }

    private static func loadOrderingOverrides(
        from defaults: UserDefaults,
        key: String
    ) -> [String: PromptOrderingMode] {
        guard let data = defaults.data(forKey: key),
              let rawOverrides = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return rawOverrides.reduce(into: [String: PromptOrderingMode]()) { partialResult, entry in
            if let mode = PromptOrderingMode(rawValue: entry.value) {
                partialResult[entry.key] = mode
            }
        }
    }

    private func persistPromptOrderingOverrides() {
        let rawOverrides = promptOrderingOverridesByCategoryID.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(rawOverrides) else {
            return
        }
        defaults.set(data, forKey: Keys.promptOrderingOverridesByCategoryID)
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
