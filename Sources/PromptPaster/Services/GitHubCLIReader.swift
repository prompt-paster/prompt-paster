import Foundation
import Darwin

protocol GitHubCLIReading: Sendable {
    func read(endpoint: String) async throws -> Data
}

struct GitHubCLIReader: GitHubCLIReading {
    static var executableURL: URL? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    func read(endpoint: String) async throws -> Data {
        guard let executable = Self.executableURL else { throw CommandError.unavailable }
        return try await BoundedCommand.run(executable: executable, arguments: [
            "api", "--hostname", "github.com", "--method", "GET",
            "--header", "Accept: application/vnd.github+json",
            "--header", "X-GitHub-Api-Version: 2022-11-28", endpoint
        ])
    }

    enum CommandError: Error, LocalizedError {
        case unavailable, timedOut, outputTooLarge, failed
        var errorDescription: String? {
            switch self {
            case .unavailable: "GitHub CLI was not found. Install gh, run 'gh auth login', or choose App token."
            case .timedOut: "GitHub CLI timed out. Check connectivity and 'gh auth status'."
            case .outputTooLarge: "GitHub returned a file larger than the supported prompt size."
            case .failed: "GitHub CLI could not read the file. Check 'gh auth status' and repository access."
            }
        }
    }
}

enum BoundedCommand {
    static func run(
        executable: URL, arguments: [String], timeout: TimeInterval = 20,
        maximumBytes: Int = 4 * 1_024 * 1_024
    ) async throws -> Data {
        try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let pipe = Pipe()
            process.standardOutput = pipe
            let control = CommandControl(process: process)
            let timeoutWork = DispatchWorkItem { control.stop(.timedOut) }
            do { try process.run() } catch { throw GitHubCLIReader.CommandError.failed }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            defer {
                timeoutWork.cancel()
                control.finish()
                try? pipe.fileHandleForReading.close()
            }
            var data = Data()
            do {
                while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                    guard data.count + chunk.count <= maximumBytes else {
                        control.stop(.outputTooLarge)
                        break
                    }
                    data.append(chunk)
                }
            } catch { control.stop(.failed) }
            process.waitUntilExit()
            if let failure = control.failure { throw failure }
            guard process.terminationStatus == 0 else { throw GitHubCLIReader.CommandError.failed }
            return data
        }.value
    }
}

private final class CommandControl: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var completed = false
    private var storedFailure: GitHubCLIReader.CommandError?
    init(process: Process) { self.process = process }
    var failure: GitHubCLIReader.CommandError? { lock.withLock { storedFailure } }
    func finish() { lock.withLock { completed = true } }
    func stop(_ failure: GitHubCLIReader.CommandError) {
        lock.withLock {
            guard !completed else { return }
            if storedFailure == nil { storedFailure = failure }
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
            lock.withLock {
                if !completed, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}
