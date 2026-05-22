import XCTest
@testable import PromptPaster

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsUseDoubleControlFallbackAndCopiedConfirmation() {
        let defaults = makeDefaults()
        let loginItemManager = FakeLoginItemManager(isEnabled: false)
        let store = SettingsStore(defaults: defaults, loginItemManager: loginItemManager)

        XCTAssertEqual(store.triggerMode, .doubleControlWithFallback)
        XCTAssertEqual(store.doubleControlThresholdMilliseconds, 350)
        XCTAssertEqual(store.doubleControlConfiguration.tapThreshold, 0.35)
        XCTAssertTrue(store.showCopiedConfirmation)
        XCTAssertFalse(store.launchAtLoginEnabled)
    }

    func testPersistsTriggerThresholdAndConfirmationPreference() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())

        store.triggerMode = .fallbackHotkeyOnly
        store.setDoubleControlThresholdMilliseconds(425)
        store.showCopiedConfirmation = false

        let reloadedStore = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())
        XCTAssertEqual(reloadedStore.triggerMode, .fallbackHotkeyOnly)
        XCTAssertEqual(reloadedStore.doubleControlThresholdMilliseconds, 425)
        XCTAssertFalse(reloadedStore.showCopiedConfirmation)
    }

    func testClampsPersistedThresholdIntoSupportedRange() {
        let defaults = makeDefaults()
        defaults.set(100, forKey: "settings.doubleControlThresholdMilliseconds")

        let lowStore = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())
        XCTAssertEqual(lowStore.doubleControlThresholdMilliseconds, 250)

        lowStore.setDoubleControlThresholdMilliseconds(900)
        XCTAssertEqual(lowStore.doubleControlThresholdMilliseconds, 700)
    }

    func testLaunchAtLoginToggleUsesLoginItemManager() {
        let defaults = makeDefaults()
        let loginItemManager = FakeLoginItemManager(isEnabled: false)
        let store = SettingsStore(defaults: defaults, loginItemManager: loginItemManager)

        store.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(store.launchAtLoginEnabled)
        XCTAssertEqual(loginItemManager.requestedValues, [true])
        XCTAssertNil(store.launchAtLoginErrorMessage)
    }

    func testLaunchAtLoginErrorRestoresSystemState() {
        let defaults = makeDefaults()
        let loginItemManager = FakeLoginItemManager(
            isEnabled: false,
            error: FakeLoginItemError.denied
        )
        let store = SettingsStore(defaults: defaults, loginItemManager: loginItemManager)

        store.setLaunchAtLoginEnabled(true)

        XCTAssertFalse(store.launchAtLoginEnabled)
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
    var isLaunchAtLoginEnabled: Bool
    var requestedValues: [Bool] = []
    private let error: Error?

    init(isEnabled: Bool = false, error: Error? = nil) {
        self.isLaunchAtLoginEnabled = isEnabled
        self.error = error
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        requestedValues.append(isEnabled)
        if let error {
            throw error
        }
        isLaunchAtLoginEnabled = isEnabled
    }
}

private enum FakeLoginItemError: Error, LocalizedError {
    case denied

    var errorDescription: String? {
        "denied"
    }
}
