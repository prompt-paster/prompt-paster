import Foundation
import Darwin

enum LibraryFileAccess {
    static func withLock<T>(at url: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw posixError() }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        guard rename(temporary.path, url.path) == 0 else { throw posixError() }
    }

    static func backup(_ data: Data, beside url: URL) throws -> URL {
        let folder = url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = folder.appendingPathComponent("prompts-\(date)-\(UUID().uuidString).json")
        try write(data, to: target)
        return target
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}

struct LibraryPatchResult {
    let library: PromptLibrary
    let changed: Bool
    let backupURL: URL?
}

enum LibraryPatch {
    private static let allowedKeys: [String: Set<String>] = [
        "prompts": ["id", "title", "body", "category", "shortcut", "tags", "updatedAt"],
        "githubSources": ["id", "title", "owner", "repository", "ref", "path", "category", "tags", "authentication", "content"],
        "composites": ["id", "title", "componentPromptIDs", "separator", "category", "tags"]
    ]

    static func merging(_ patch: Data, into library: PromptLibrary) throws -> PromptLibrary {
        guard let input = try JSONSerialization.jsonObject(with: patch) as? [String: Any] else {
            throw LibraryCommandError.message("The manifest must be a JSON object.")
        }
        guard Set(input.keys).isSubset(of: Set(allowedKeys.keys).union(["version"])) else {
            throw LibraryCommandError.message("Unknown manifest key. Allowed keys: version, prompts, githubSources, composites.")
        }
        var document = try JSONSerialization.jsonObject(with: PromptLibraryCoding.makeEncoder().encode(library)) as! [String: Any]
        if let version = input["version"] { document["version"] = version }
        for (collection, fields) in allowedKeys {
            guard let value = input[collection] else { continue }
            guard let entries = value as? [[String: Any]] else {
                throw LibraryCommandError.message("\(collection) must be an array of objects.")
            }
            var current = document[collection] as? [[String: Any]] ?? []
            var seen = Set<String>()
            for entry in entries {
                guard Set(entry.keys).isSubset(of: fields), let id = entry["id"] as? String, !id.isEmpty else {
                    throw LibraryCommandError.message("Invalid \(collection) entry: check its id and field names.")
                }
                guard seen.insert(id).inserted else { throw PromptSourceValidationError.duplicatePromptID(id) }
                if let index = current.firstIndex(where: { $0["id"] as? String == id }) {
                    current[index].merge(entry, uniquingKeysWith: { _, new in new })
                } else { current.append(entry) }
            }
            document[collection] = current
        }
        let updated = try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: JSONSerialization.data(withJSONObject: document))
        let validation = try updated.validated()
        if validation.warnings.contains(where: { if case .duplicateID = $0 { return true }; return false }) {
            throw LibraryCommandError.message("The library contains duplicate local IDs. Resolve them before applying a manifest.")
        }
        return updated
    }

    static func apply(_ data: Data, to url: URL, dryRun: Bool) throws -> LibraryPatchResult {
        try LibraryFileAccess.withLock(at: url) {
            let oldData = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            let library = try oldData.map { try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: $0) }
                ?? PromptLibrary(prompts: [])
            let updated = try merging(data, into: library)
            let changed = oldData == nil || updated != library
            var backup: URL?
            if changed, !dryRun {
                if let oldData { backup = try LibraryFileAccess.backup(oldData, beside: url) }
                try LibraryFileAccess.write(PromptLibraryCoding.makeEncoder().encode(updated), to: url)
            }
            return LibraryPatchResult(library: updated, changed: changed, backupURL: backup)
        }
    }
}

enum LibraryCommandError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
