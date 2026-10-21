import Foundation
import Security

protocol GitHubPromptSourceFetching: Sendable {
    func fetchPrompts(
        for sources: [GitHubPromptSource],
        token: String?
    ) async -> (prompts: [Prompt], errors: [String])
}

struct GitHubPromptSourceService: GitHubPromptSourceFetching, Sendable {
    private struct ContentsResponse: Decodable {
        let content: String
        let encoding: String
    }

    func fetchPrompts(
        for sources: [GitHubPromptSource],
        token: String?
    ) async -> (prompts: [Prompt], errors: [String]) {
        await withTaskGroup(of: Result<Prompt, Error>.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        return .success(try await fetchPrompt(for: source, token: token))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var prompts: [Prompt] = []
            var errors: [String] = []
            for await result in group {
                switch result {
                case .success(let prompt): prompts.append(prompt)
                case .failure(let error): errors.append(error.localizedDescription)
                }
            }
            return (prompts.sorted { $0.id < $1.id }, errors.sorted())
        }
    }

    private func fetchPrompt(for source: GitHubPromptSource, token: String?) async throws -> Prompt {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(source.owner)/\(source.repository)/contents/\(source.path)"
        components.queryItems = [URLQueryItem(name: "ref", value: source.ref)]
        guard let url = components.url else {
            throw GitHubPromptSourceServiceError.invalidURL(source.title)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PromptPaster", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubPromptSourceServiceError.invalidResponse(source.title)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubPromptSourceServiceError.httpStatus(
                source: source.title,
                statusCode: httpResponse.statusCode
            )
        }

        let contents = try JSONDecoder().decode(ContentsResponse.self, from: data)
        guard contents.encoding == "base64",
              let decoded = Data(base64Encoded: contents.content, options: .ignoreUnknownCharacters),
              let body = String(data: decoded, encoding: .utf8)
        else {
            throw GitHubPromptSourceServiceError.invalidContent(source.title)
        }

        return Prompt(
            id: source.promptID,
            title: source.title,
            category: source.category,
            body: body,
            tags: source.tags + ["github", source.owner, source.repository],
            updatedAt: Date()
        )
    }
}

enum GitHubPromptSourceServiceError: Error, LocalizedError {
    case invalidURL(String)
    case invalidResponse(String)
    case httpStatus(source: String, statusCode: Int)
    case invalidContent(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let title): "GitHub source \"\(title)\" has an invalid URL."
        case .invalidResponse(let title): "GitHub source \"\(title)\" returned an invalid response."
        case .httpStatus(let source, let statusCode):
            "GitHub source \"\(source)\" could not load (HTTP \(statusCode)). Check its repository, ref, path, and token."
        case .invalidContent(let title): "GitHub source \"\(title)\" did not contain UTF-8 text."
        }
    }
}

@MainActor
final class GitHubCredentialStore: ObservableObject {
    static let service = "com.shaypal5.prompt-paster.github-token"
    private let account = "default"

    @Published private(set) var hasToken: Bool
    @Published private(set) var errorMessage: String?

    init() {
        hasToken = Self.readToken(service: Self.service, account: "default") != nil
    }

    var token: String? {
        Self.readToken(service: Self.service, account: account)
    }

    func saveToken(_ token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmedToken.isEmpty {
                try deleteToken()
            } else {
                try Self.writeToken(trimmedToken, service: Self.service, account: account)
            }
            hasToken = !trimmedToken.isEmpty
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubCredentialStoreError.keychain(status)
        }
        hasToken = false
    }

    private static func readToken(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeToken(_ token: String, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var createQuery = query
            createQuery[kSecValueData as String] = Data(token.utf8)
            let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard createStatus == errSecSuccess else {
                throw GitHubCredentialStoreError.keychain(createStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw GitHubCredentialStoreError.keychain(updateStatus)
        }
    }
}

enum GitHubCredentialStoreError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status): "Could not update the GitHub token in Keychain (\(status))."
        }
    }
}
