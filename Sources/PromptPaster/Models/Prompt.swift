import Foundation

struct Prompt: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let category: String?
    let body: String
    let shortcut: String?
    let tags: [String]
    let updatedAt: Date?

    init(
        id: String,
        title: String,
        category: String? = nil,
        body: String,
        shortcut: String? = nil,
        tags: [String] = [],
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.shortcut = shortcut
        self.tags = tags
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case body
        case shortcut
        case tags
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        body = try container.decode(String.self, forKey: .body)
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}
