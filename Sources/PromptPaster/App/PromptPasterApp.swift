import AppKit

@main
enum PromptPasterApp {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty, !arguments[0].hasPrefix("-psn_"), AppLaunchAction(arguments: arguments) == nil {
            Task { exit(await LibraryCommandLine.run(arguments: arguments)) }
            RunLoop.main.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate(launchAction: AppLaunchAction(arguments: arguments))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// Explicit GUI entry points for agent handoffs; library subcommands stay headless.
enum AppLaunchAction: String {
    case show = "--show"
    case editLibrary = "--edit-library"
    case settings = "--settings"

    init?(arguments: [String]) {
        guard arguments.count == 1, let action = Self(rawValue: arguments[0]) else { return nil }
        self = action
    }
}
