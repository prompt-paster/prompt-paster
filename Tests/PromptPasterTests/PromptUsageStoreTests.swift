import XCTest
@testable import PromptPaster

@MainActor
final class PromptUsageStoreTests: XCTestCase {
    func testRecordsAndPersistsPromptUsageStats() {
        let defaults = makeDefaults()
        let store = PromptUsageStore(defaults: defaults)
        let firstCopyDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondCopyDate = Date(timeIntervalSince1970: 1_700_000_100)

        store.recordPromptCopy(promptID: "handoff", copiedAt: firstCopyDate)
        store.recordPromptCopy(promptID: "handoff", copiedAt: secondCopyDate)
        store.recordPromptCopy(promptID: "merge-check", copiedAt: firstCopyDate)

        let reloadedStore = PromptUsageStore(defaults: defaults)
        XCTAssertEqual(
            reloadedStore.statsByPromptID["handoff"],
            PromptUsageStats(copyCount: 2, lastCopiedAt: secondCopyDate)
        )
        XCTAssertEqual(
            reloadedStore.statsByPromptID["merge-check"],
            PromptUsageStats(copyCount: 1, lastCopiedAt: firstCopyDate)
        )
        XCTAssertNil(reloadedStore.lastErrorMessage)
    }

    func testPrunesStatsForRemovedPromptIDs() {
        let defaults = makeDefaults()
        let store = PromptUsageStore(defaults: defaults)

        store.recordPromptCopy(promptID: "keep")
        store.recordPromptCopy(promptID: "remove")
        store.pruneKeepingPromptIDs(["keep"])

        XCTAssertEqual(Set(store.statsByPromptID.keys), ["keep"])

        let reloadedStore = PromptUsageStore(defaults: defaults)
        XCTAssertEqual(Set(reloadedStore.statsByPromptID.keys), ["keep"])
    }

    func testCorruptPersistedStatsResetWithVisibleError() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: "usage.promptUsageStats")

        let store = PromptUsageStore(defaults: defaults)

        XCTAssertEqual(store.statsByPromptID, [:])
        XCTAssertEqual(
            store.lastErrorMessage,
            "Saved prompt usage stats could not be read. Usage ranking was reset."
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PromptPasterTests.PromptUsageStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
