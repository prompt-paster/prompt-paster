import Foundation

struct PromptHomeSlot: Codable, Equatable, Identifiable {
    let promptID: String
    var key: String

    var id: String { promptID }
}

enum PromptHomeConfiguration {
    static let defaultKeys = ["a", "s", "d", "f", "g", "h", "j", "k", "l", "q", "w", "e", "r", "t", "y", "u"]
    static let maximumPromptCount = defaultKeys.count

    static func normalizedSlots(_ slots: [PromptHomeSlot]) -> [PromptHomeSlot] {
        var usedPromptIDs = Set<String>()
        var usedKeys = Set<String>()

        return slots.compactMap { slot in
            let normalizedKey = normalizedKey(slot.key)
            guard !slot.promptID.isEmpty,
                  !normalizedKey.isEmpty,
                  usedPromptIDs.insert(slot.promptID).inserted,
                  usedKeys.insert(normalizedKey).inserted
            else { return nil }
            return PromptHomeSlot(promptID: slot.promptID, key: normalizedKey)
        }
        .prefix(maximumPromptCount)
        .map { $0 }
    }

    static func nextAvailableKey(excluding slots: [PromptHomeSlot]) -> String? {
        let usedKeys = Set(slots.map(\.key))
        return defaultKeys.first { !usedKeys.contains($0) }
    }

    static func normalizedKey(_ key: String) -> String {
        let characters = key.lowercased().filter { $0.isLetter }
        return characters.count == 1 ? characters : ""
    }
}
