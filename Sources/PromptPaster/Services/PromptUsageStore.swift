import Foundation

struct PromptUsageStats: Codable, Equatable {
    let copyCount: Int
    let lastCopiedAt: Date?

    static let empty = PromptUsageStats(copyCount: 0, lastCopiedAt: nil)
}

@MainActor
final class PromptUsageStore: ObservableObject {
    private enum Keys {
        static let promptUsageStats = "usage.promptUsageStats"
    }

    @Published private(set) var statsByPromptID: [Prompt.ID: PromptUsageStats]
    @Published private(set) var lastErrorMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        do {
            self.statsByPromptID = try Self.loadStats(from: defaults, key: Keys.promptUsageStats)
            self.lastErrorMessage = nil
        } catch {
            self.statsByPromptID = [:]
            self.lastErrorMessage = error.localizedDescription
        }
    }

    func recordPromptCopy(promptID: Prompt.ID, copiedAt: Date = Date()) {
        let currentStats = statsByPromptID[promptID] ?? .empty
        statsByPromptID[promptID] = PromptUsageStats(
            copyCount: currentStats.copyCount + 1,
            lastCopiedAt: copiedAt
        )
        persistStats()
    }

    func pruneKeepingPromptIDs(_ promptIDs: Set<Prompt.ID>) {
        let prunedStats = statsByPromptID.filter { promptIDs.contains($0.key) }
        guard prunedStats.count != statsByPromptID.count else {
            return
        }

        statsByPromptID = prunedStats
        persistStats()
    }

    private static func loadStats(
        from defaults: UserDefaults,
        key: String
    ) throws -> [Prompt.ID: PromptUsageStats] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([Prompt.ID: PromptUsageStats].self, from: data)
        } catch {
            throw PromptUsageStoreError.invalidPersistedStats
        }
    }

    private func persistStats() {
        do {
            let data = try JSONEncoder().encode(statsByPromptID)
            defaults.set(data, forKey: Keys.promptUsageStats)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

enum PromptUsageStoreError: LocalizedError, Equatable {
    case invalidPersistedStats

    var errorDescription: String? {
        switch self {
        case .invalidPersistedStats:
            "Saved prompt usage stats could not be read. Usage ranking was reset."
        }
    }
}
