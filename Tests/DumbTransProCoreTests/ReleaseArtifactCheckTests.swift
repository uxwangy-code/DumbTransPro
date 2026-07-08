import Foundation
import Testing

struct ReleaseArtifactCheckTests {
    @Test func releaseArtifactCheckFailsWhenTelemetryURLIsMissing() throws {
        let appURL = try makeAppBundle(info: [
            "CFBundleShortVersionString": "1.5.2",
            "CFBundleVersion": "152",
            "DTPLicensePurchaseURL": "https://uxwangy-code.github.io/DumbTransPro/#pricing",
            "DTPLicenseVerifyURL": "https://license.whimsycode.com/api/licenses/verify",
        ])

        let result = try runCheckScript(appURL: appURL)

        #expect(result.exitCode != 0)
        #expect(result.output.contains("DTPUsageTelemetryURL"))
    }

    @Test func releaseArtifactCheckPassesWhenRequiredReleaseURLsMatch() throws {
        let appURL = try makeAppBundle(info: [
            "CFBundleShortVersionString": "1.5.2",
            "CFBundleVersion": "152",
            "DTPUsageTelemetryURL": "https://telemetry.whimsycode.com/events",
            "DTPLicensePurchaseURL": "https://uxwangy-code.github.io/DumbTransPro/#pricing",
            "DTPLicenseVerifyURL": "https://license.whimsycode.com/api/licenses/verify",
        ])

        let result = try runCheckScript(appURL: appURL)

        #expect(result.exitCode == 0)
    }

    private func runCheckScript(appURL: URL) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repoRoot().appendingPathComponent("scripts/check-release-artifact.sh").path]
        process.environment = [
            "DUMBTRANS_RELEASE_APP_PATH": appURL.path,
            "DUMBTRANS_EXPECTED_VERSION": "1.5.2",
            "DUMBTRANS_EXPECTED_BUILD": "152",
            "DUMBTRANS_EXPECTED_USAGE_TELEMETRY_URL": "https://telemetry.whimsycode.com/events",
            "DUMBTRANS_EXPECTED_LICENSE_PURCHASE_URL": "https://uxwangy-code.github.io/DumbTransPro/#pricing",
            "DUMBTRANS_EXPECTED_LICENSE_VERIFY_URL": "https://license.whimsycode.com/api/licenses/verify",
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }

    private func makeAppBundle(info: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumbTransProTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("DumbTransPro.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try plistData.write(to: plistURL)
        return appURL
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct CommandResult {
    let exitCode: Int32
    let output: String
}
