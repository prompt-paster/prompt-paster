import Foundation

@MainActor
enum LibraryCommandLine {
    static let help = """
    Prompt Paster agent CLI
    Usage: PromptPaster library <command> [--library /absolute/path/prompts.json]
      info                    Show library location and counts
      list                    List local prompts, sources, and composites as JSON
      export                  Export the complete library as JSON
      example                 Print an apply-ready source/composite manifest
      validate                Validate the library without network access
      apply MANIFEST|-        Merge entries by ID, preserving unrelated entries
        --dry-run             Validate the merge without writing the library
      refresh                 Fetch sources and check composites; JSON, no prompt bodies
      render ID               Print the complete resolved prompt (fresh GitHub fetch)
      favorites ID ...        Add home favorites (default library only)
    PromptPaster --version | --help
    GUI startup: PromptPaster --show | --edit-library | --settings
    Private repositories: authentication=githubCLI uses your existing gh auth login.
    apply makes a private backup before changing an existing library. No auto-paste.
    """

    static func run(arguments: [String]) async -> Int32 {
        do {
            if arguments == ["--help"] || arguments == ["-h"] { print(help); return 0 }
            if arguments == ["--version"] {
                print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
                return 0
            }
            guard arguments.first == "library" else { throw LibraryCommandError.message(help) }
            var args = Array(arguments.dropFirst())
            let defaultURL = PromptStore.defaultApplicationSupportURL().appendingPathComponent(PromptStore.libraryFileName)
            var url = defaultURL
            if let index = args.firstIndex(of: "--library") {
                guard index + 1 < args.count, args[index + 1].hasPrefix("/") else {
                    throw LibraryCommandError.message("--library requires an absolute file path.")
                }
                url = URL(fileURLWithPath: args[index + 1]).standardizedFileURL
                args.removeSubrange(index...index + 1)
            }
            guard let command = args.first else { throw LibraryCommandError.message(help) }
            args.removeFirst()
            if command == "example" {
                try requireNoArguments(args)
                try emitJSON([
                    "githubSources": [["id": "team-base", "title": "Team base", "owner": "example",
                        "repository": "team-wiki", "ref": "main", "path": "prompts/base.md",
                        "authentication": "githubCLI", "content": "pasteReadyBlock"]],
                    "composites": [["id": "team-start", "title": "Team start",
                        "componentPromptIDs": ["github-team-base"], "separator": "\n\n"]]
                ])
                return 0
            }
            if command == "apply" {
                let dryRun = args.contains("--dry-run")
                args.removeAll { $0 == "--dry-run" }
                guard args.count == 1 else { throw LibraryCommandError.message("apply requires a manifest file or - for stdin.") }
                let data = args[0] == "-" ? FileHandle.standardInput.readDataToEndOfFile()
                    : try Data(contentsOf: URL(fileURLWithPath: args[0]))
                guard data.count <= 16 * 1_024 * 1_024 else { throw LibraryCommandError.message("Manifest exceeds 16 MiB.") }
                let result = try LibraryPatch.apply(data, to: url, dryRun: dryRun)
                var output = summary(result.library, url: url)
                output["changed"] = result.changed
                output["dryRun"] = dryRun
                if let backup = result.backupURL { output["backup"] = backup.path }
                try emitJSON(output)
                return 0
            }
            let exists = FileManager.default.fileExists(atPath: url.path)
            let library: PromptLibrary
            if exists { library = try PromptLibraryCoding.makeDecoder().decode(PromptLibrary.self, from: Data(contentsOf: url)) }
            else { library = PromptLibrary(prompts: []) }
            let loaded = try library.validatedForLoading()
            switch command {
            case "info":
                try requireNoArguments(args)
                var output = summary(loaded.library, url: url)
                output["exists"] = exists
                output["githubCLIAvailable"] = GitHubCLIReader.executableURL != nil
                try emitJSON(output)
            case "list":
                try requireNoArguments(args)
                try emitJSON(["prompts": loaded.library.prompts.map { ["id": $0.id, "title": $0.title] },
                    "githubSources": try object(loaded.library.githubSources),
                    "composites": try object(loaded.library.composites)])
            case "export":
                try requireNoArguments(args)
                FileHandle.standardOutput.write(try PromptLibraryCoding.makeEncoder().encode(library))
                print("")
            case "validate":
                try requireNoArguments(args)
                guard exists else { throw LibraryCommandError.message("Library does not exist. Use apply to create it.") }
                var output = summary(loaded.library, url: url)
                output["valid"] = true
                output["warnings"] = loaded.validation.warnings.count
                try emitJSON(output)
            case "favorites":
                guard url.standardizedFileURL == defaultURL.standardizedFileURL else {
                    throw LibraryCommandError.message("favorites only supports the installed app's default library.")
                }
                guard !args.isEmpty else { throw LibraryCommandError.message("favorites requires one or more prompt IDs.") }
                let known = Set(library.prompts.map(\.id) + library.githubSources.map(\.promptID) + library.composites.map(\.id))
                guard args.allSatisfy(known.contains) else { throw LibraryCommandError.message("Unknown favorite ID. Use library list.") }
                let defaults = try appDefaults()
                let settings = SettingsStore(defaults: defaults)
                let additional = Set(args).subtracting(settings.homePromptSlots.map(\.promptID))
                guard additional.count + settings.homePromptSlots.count <= PromptHomeConfiguration.maximumPromptCount else {
                    throw LibraryCommandError.message("Home has reached its limit of \(PromptHomeConfiguration.maximumPromptCount) favorites. Remove a favorite in Settings before adding more.")
                }
                for id in args where !settings.isFavorite(promptID: id) { settings.toggleFavorite(promptID: id) }
                settings.homeScreenEnabled = true
                defaults.synchronize()
                try emitJSON(["homePromptSlots": try object(settings.homePromptSlots)])
            case "refresh", "render":
                if command == "refresh" { try requireNoArguments(args) }
                else {
                    guard args.count == 1 else { throw LibraryCommandError.message("render requires one prompt ID.") }
                    if let local = library.prompts.first(where: { $0.id == args[0] }) { print(local.body); return 0 }
                }
                let token = library.githubSources.contains(where: { $0.authentication == .storedToken })
                    ? GitHubCredentialStore().token : nil
                let result = await GitHubPromptSourceService().fetchPrompts(for: library.githubSources, token: token)
                let base = loaded.library.prompts + result.prompts
                let composites = CompositePromptResolver.resolve(library.composites, against: base)
                let errors = result.errors + composites.warnings
                let effective = base + composites.prompts
                if command == "render" {
                    guard let prompt = effective.first(where: { $0.id == args[0] }) else {
                        throw LibraryCommandError.message((errors + ["Prompt is unavailable: \(args[0])."]).joined(separator: "\n"))
                    }
                    print(prompt.body)
                } else {
                    try emitJSON(["prompts": effective.map { ["id": $0.id, "title": $0.title, "characters": $0.body.count] as [String: Any] },
                                  "errors": errors])
                    return errors.isEmpty ? 0 : 1
                }
            default: throw LibraryCommandError.message(help)
            }
            return 0
        } catch {
            if let data = try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription], options: [.sortedKeys]) {
                FileHandle.standardError.write(data + Data("\n".utf8))
            }
            return 1
        }
    }

    // A bundle cannot add its own identifier as an additional suite. The installed
    // executable already uses the app domain through .standard; SwiftPM binaries
    // need the named suite to reach that same domain.
    static func appDefaults(bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> UserDefaults {
        let appIdentifier = "com.shaypal5.prompt-paster"
        if bundleIdentifier == appIdentifier { return .standard }
        guard let defaults = UserDefaults(suiteName: appIdentifier) else {
            throw LibraryCommandError.message("Could not open Prompt Paster preferences.")
        }
        return defaults
    }

    private static func requireNoArguments(_ args: [String]) throws {
        guard args.isEmpty else { throw LibraryCommandError.message("Unexpected arguments: \(args.joined(separator: " ")).") }
    }
    private static func summary(_ library: PromptLibrary, url: URL) -> [String: Any] {
        ["library": url.path, "version": library.version, "localPrompts": library.prompts.count,
         "githubSources": library.githubSources.count, "composites": library.composites.count]
    }
    private static func object<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: PromptLibraryCoding.makeEncoder().encode(value))
    }
    private static func emitJSON(_ object: Any) throws {
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8))
    }
}
