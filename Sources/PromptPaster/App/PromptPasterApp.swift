import AppKit

@main
enum PromptPasterApp {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if !arguments.isEmpty, !arguments[0].hasPrefix("-psn_") {
            Task { exit(await LibraryCommandLine.run(arguments: arguments)) }
            RunLoop.main.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
