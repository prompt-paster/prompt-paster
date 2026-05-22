import XCTest
@testable import PromptPaster

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsUseDoubleControlFallback() {
        let defaults = makeDefaults()
        let loginItemManager = FakeLoginItemManager(status: .disabled)
        let store = SettingsStore(defaults: defaults, loginItemManager: loginItemManager)

        XCTAssertEqual(store.triggerMode, .doubleControlWithFallback)
        XCTAssertEqual(store.doubleControlThresholdMilliseconds, 350)
        XCTAssertEqual(store.doubleControlConfiguration.tapThreshold, 0.35)
        XCTAssertEqual(store.launchAtLoginStatus, .disabled)
    }

    func testPersistsTriggerAndThresholdPreference() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())

        store.triggerMode = .fallbackHotkeyOnly
        store.setDoubleControlThresholdMilliseconds(425)

        let reloadedStore = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())
        XCTAssertEqual(reloadedStore.triggerMode, .fallbackHotkeyOnly)
        XCTAssertEqual(reloadedStore.doubleControlThresholdMilliseconds, 425)
    }

    func testClampsPersistedThresholdIntoSupportedRange() {
        let defaults = makeDefaults()
        let seedStore = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())
        seedStore.setDoubleControlThresholdMilliseconds(100)

        let lowStore = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())
        XCTAssertEqual(lowStore.doubleControlThresholdMilliseconds, 250)

        lowStore.setDoubleControlThresholdMilliseconds(900)
        XCTAssertEqual(lowStore.doubleControlThresholdMilliseconds, 700)
    }

    func testLaunchAtLoginToggleUsesLoginItemManager() {
        let defaults = makeDefaults()
        let loginItemManager = FakeLoginItemManager(status: .disabled)
        let store = SettingsStore(defaults: defaults, loginItemManager: loginItemManager)

        store.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(store.launchAtLoginStatus, .enabled)
        XCTAssertEqual(loginItemManager.requestedValues, [true])
        XCTAssertNil(store.launchAtLoginErrorMessage)
    }

    func testLaunchAtLoginApprovalNeededIsDistinctFromDisabled() {
        let defaults = makeDefaults()
        let loginItemManager = FakeLoginItemManager(status: .requiresApproval)
        let store = SettingsStore(defaults: defaults, loginItemManager: loginItemManager)

        XCTAssertEqual(store.launchAtLoginStatus, .requiresApproval)
        XCTAssertTrue(store.launchAtLoginStatus.isToggleOn)
        XCTAssertEqual(store.launchAtLoginStatus.displayValue, "Requires approval")

        store.setLaunchAtLoginEnabled(false)

        XCTAssertEqual(store.launchAtLoginStatus, .disabled)
        XCTAssertEqual(loginItemManager.requestedValues, [false])
    }

    func testOpenLoginItemsSettingsForwardsToManager() {
        let loginItemManager = FakeLoginItemManager()
        let store = SettingsStore(defaults: makeDefaults(), loginItemManager: loginItemManager)

        store.openLoginItemsSettings()

        XCTAssertEqual(loginItemManager.openSettingsCount, 1)
    }

    func testLaunchAtLoginErrorRestoresSystemState() {
        let defaults = makeDefaults()
        let loginItemManager = FakeLoginItemManager(
            status: .disabled,
            error: FakeLoginItemError.denied
        )
        let store = SettingsStore(defaults: defaults, loginItemManager: loginItemManager)

        store.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(store.launchAtLoginStatus, .disabled)
        XCTAssertEqual(store.launchAtLoginErrorMessage, "denied")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PromptPasterTests.SettingsStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FakeLoginItemManager: LoginItemManaging {
    var launchAtLoginStatus: LaunchAtLoginStatus
    var requestedValues: [Bool] = []
    var openSettingsCount = 0
    private let error: Error?

    init(status: LaunchAtLoginStatus = .disabled, error: Error? = nil) {
        self.launchAtLoginStatus = status
        self.error = error
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        requestedValues.append(isEnabled)
        if let error {
            throw error
        }
        launchAtLoginStatus = isEnabled ? .enabled : .disabled
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}

private enum FakeLoginItemError: Error, LocalizedError {
    case denied

    var errorDescription: String? {
        "denied"
    }
}
