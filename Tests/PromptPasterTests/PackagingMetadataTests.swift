import XCTest

final class PackagingMetadataTests: XCTestCase {
    func testInfoPlistHasReleasePackagingMetadata() throws {
        let plistURL = try repositoryRoot()
            .appendingPathComponent("Packaging")
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "PromptPaster")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.shaypal5.prompt-paster")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "PromptPaster")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertNotNil(plist["CFBundleShortVersionString"] as? String)
        XCTAssertNotNil(plist["CFBundleVersion"] as? String)
    }

    func testPackagingScriptsAreExecutable() throws {
        let root = try repositoryRoot()
        let scripts = [
            "build-app.sh",
            "build-dmg.sh",
            "generate-app-icon.sh",
            "generate-status-icon-preview.sh",
            "validate-release-package.sh"
        ]

        for script in scripts {
            let path = root.appendingPathComponent("scripts").appendingPathComponent(script).path
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path), "\(script) should be executable")
        }
    }

    func testNotarizationRequiresSigningIdentityBeforeBuilding() throws {
        let root = try repositoryRoot()
        let result = try runBashScript(
            root.appendingPathComponent("scripts").appendingPathComponent("build-dmg.sh"),
            currentDirectory: root,
            environment: [
                "NOTARIZE": "1",
                "CODESIGN_IDENTITY": ""
            ]
        )

        XCTAssertNotEqual(result.exitStatus, 0)
        XCTAssertTrue(
            result.output.contains("NOTARIZE=1 requires CODESIGN_IDENTITY"),
            "Expected signing preflight error, got: \(result.output)"
        )
        XCTAssertFalse(
            result.output.contains("Building for production"),
            "Preflight should fail before invoking swift build"
        )
    }

    func testReleaseWorkflowBuildsValidatesAndPublishesDMG() throws {
        let workflowURL = try repositoryRoot()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("release.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)

        XCTAssertTrue(workflow.contains("workflow_dispatch"))
        XCTAssertTrue(workflow.contains("runs-on: macos-14"))
        XCTAssertTrue(workflow.contains("DEVELOPER_DIR: /Applications/Xcode_16.2.app/Contents/Developer"))
        XCTAssertTrue(workflow.contains("swift --version"))
        XCTAssertTrue(workflow.contains("push:"))
        XCTAssertTrue(workflow.contains("tags:"))
        XCTAssertTrue(workflow.contains("scripts/build-dmg.sh"))
        XCTAssertTrue(workflow.contains("scripts/validate-release-package.sh \"$DMG_PATH\" --launch-smoke"))
        XCTAssertTrue(workflow.contains("actions/upload-artifact@v4"))
        XCTAssertTrue(workflow.contains("gh release create"))
        XCTAssertTrue(workflow.contains("gh release upload"))
    }

    func testReleaseWorkflowSupportsSigningAndNotarizationSecrets() throws {
        let workflowURL = try repositoryRoot()
            .appendingPathComponent(".github")
            .appendingPathComponent("workflows")
            .appendingPathComponent("release.yml")
        let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
        let requiredSecretNames = [
            "APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64",
            "APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD",
            "CODESIGN_IDENTITY",
            "APPLE_ID",
            "APPLE_TEAM_ID",
            "APP_SPECIFIC_PASSWORD"
        ]

        for secretName in requiredSecretNames {
            XCTAssertTrue(workflow.contains(secretName), "Release workflow should reference \(secretName)")
        }
        XCTAssertTrue(workflow.contains("security import"))
        XCTAssertTrue(workflow.contains("NOTARIZE"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }

        throw NSError(
            domain: "PackagingMetadataTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate repository root"]
        )
    }

    private func runBashScript(
        _ scriptURL: URL,
        currentDirectory: URL,
        environment: [String: String]
    ) throws -> (exitStatus: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", scriptURL.path]
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
