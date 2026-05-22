import AppKit
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
        XCTAssertEqual(store.overlaySizeMode, .percentageOfDisplay)
        XCTAssertEqual(store.overlayDisplayPercentage, 80)
        XCTAssertEqual(store.overlayFixedWidthPixels, 1100)
        XCTAssertEqual(store.overlayFixedHeightPixels, 720)
        XCTAssertEqual(store.promptPreviewCharacterLimit, 260)
        XCTAssertEqual(store.promptSelectionShortcutMode, .spatialLetters)
        XCTAssertEqual(store.launchAtLoginStatus, .disabled)
    }

    func testPersistsTriggerThresholdAndOverlayPreferences() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())

        store.triggerMode = .fallbackHotkeyOnly
        store.setDoubleControlThresholdMilliseconds(425)
        store.overlaySizeMode = .fixedPixels
        store.setOverlayDisplayPercentage(65)
        store.setOverlayFixedWidthPixels(1320)
        store.setOverlayFixedHeightPixels(840)
        store.setPromptPreviewCharacterLimit(180)
        store.promptSelectionShortcutMode = .numbers

        let reloadedStore = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())
        XCTAssertEqual(reloadedStore.triggerMode, .fallbackHotkeyOnly)
        XCTAssertEqual(reloadedStore.doubleControlThresholdMilliseconds, 425)
        XCTAssertEqual(reloadedStore.overlaySizeMode, .fixedPixels)
        XCTAssertEqual(reloadedStore.overlayDisplayPercentage, 65)
        XCTAssertEqual(reloadedStore.overlayFixedWidthPixels, 1320)
        XCTAssertEqual(reloadedStore.overlayFixedHeightPixels, 840)
        XCTAssertEqual(reloadedStore.promptPreviewCharacterLimit, 180)
        XCTAssertEqual(reloadedStore.promptSelectionShortcutMode, .numbers)
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

    func testClampsOverlayDisplayPreferencesIntoSupportedRanges() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults, loginItemManager: FakeLoginItemManager())

        store.setOverlayDisplayPercentage(20)
        store.setOverlayFixedWidthPixels(100)
        store.setOverlayFixedHeightPixels(100)
        store.setPromptPreviewCharacterLimit(10)

        XCTAssertEqual(store.overlayDisplayPercentage, 40)
        XCTAssertEqual(store.overlayFixedWidthPixels, 760)
        XCTAssertEqual(store.overlayFixedHeightPixels, 480)
        XCTAssertEqual(store.promptPreviewCharacterLimit, 40)

        store.setOverlayDisplayPercentage(120)
        store.setOverlayFixedWidthPixels(3_000)
        store.setOverlayFixedHeightPixels(3_000)
        store.setPromptPreviewCharacterLimit(2_000)

        XCTAssertEqual(store.overlayDisplayPercentage, 95)
        XCTAssertEqual(store.overlayFixedWidthPixels, 2_400)
        XCTAssertEqual(store.overlayFixedHeightPixels, 1_600)
        XCTAssertEqual(store.promptPreviewCharacterLimit, 600)
    }

    func testOverlayDisplayConfigurationClampsToVisibleDisplay() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let percentageConfiguration = OverlayDisplayConfiguration(
            sizeMode: .percentageOfDisplay,
            displayPercentage: 50,
            fixedWidth: 1_100,
            fixedHeight: 720
        )

        XCTAssertEqual(percentageConfiguration.size(for: visibleFrame), CGSize(width: 520, height: 350))

        let fixedConfiguration = OverlayDisplayConfiguration(
            sizeMode: .fixedPixels,
            displayPercentage: 80,
            fixedWidth: 2_400,
            fixedHeight: 1_600
        )

        XCTAssertEqual(fixedConfiguration.size(for: visibleFrame), CGSize(width: 1_000, height: 700))
    }

    func testPercentageOverlaySizesRemainDistinctOnTypicalLaptopDisplay() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_512, height: 944)
        let fortyPercent = OverlayDisplayConfiguration(
            sizeMode: .percentageOfDisplay,
            displayPercentage: 40,
            fixedWidth: 1_100,
            fixedHeight: 720
        )
        let fiftyPercent = OverlayDisplayConfiguration(
            sizeMode: .percentageOfDisplay,
            displayPercentage: 50,
            fixedWidth: 1_100,
            fixedHeight: 720
        )

        assertSize(fortyPercent.size(for: visibleFrame), equals: CGSize(width: 604.8, height: 377.6))
        assertSize(fiftyPercent.size(for: visibleFrame), equals: CGSize(width: 756, height: 472))
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

    private func assertSize(
        _ actual: CGSize,
        equals expected: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
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
