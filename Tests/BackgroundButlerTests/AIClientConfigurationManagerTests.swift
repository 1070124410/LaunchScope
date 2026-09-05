import Foundation
import XCTest
@testable import BackgroundButler

final class AIClientConfigurationManagerTests: XCTestCase {
    func testMergesLaunchScopeWithoutReplacingExistingMCPServers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("mcp.json")
        let existing = #"{"theme":"dark","mcpServers":{"existing":{"command":"keep-me"}}}"#
        try Data(existing.utf8).write(to: file)
        let manager = AIClientConfigurationManager(homeDirectory: directory, environmentPath: "")

        let result = try manager.mergeJSONConfiguration(
            clientName: "Test Client",
            configurationURL: file,
            serverPath: "/Applications/LaunchScope.app/server.py"
        )

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["existing"])
        let launchscope = try XCTUnwrap(servers["launchscope"] as? [String: Any])
        XCTAssertEqual(launchscope["command"] as? String, "/usr/bin/python3")
        XCTAssertEqual(launchscope["args"] as? [String], ["/Applications/LaunchScope.app/server.py"])
        XCTAssertEqual(root["theme"] as? String, "dark")
        XCTAssertTrue(result.changed)
        XCTAssertNotNil(result.backupPath)
    }

    func testRepeatedJSONApplyIsIdempotent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("mcp.json")
        let manager = AIClientConfigurationManager(homeDirectory: directory, environmentPath: "")
        _ = try manager.mergeJSONConfiguration(
            clientName: "Test Client",
            configurationURL: file,
            serverPath: "/server.py"
        )

        let second = try manager.mergeJSONConfiguration(
            clientName: "Test Client",
            configurationURL: file,
            serverPath: "/server.py"
        )

        XCTAssertFalse(second.changed)
        XCTAssertNil(second.backupPath)
    }

    func testInvalidMCPServersDoesNotOverwriteConfiguration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("mcp.json")
        let existing = #"{"mcpServers":"invalid"}"#
        try Data(existing.utf8).write(to: file)
        let manager = AIClientConfigurationManager(homeDirectory: directory, environmentPath: "")

        XCTAssertThrowsError(try manager.mergeJSONConfiguration(
            clientName: "Test Client",
            configurationURL: file,
            serverPath: "/server.py"
        ))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), existing)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchScopeAIClientTests-\(UUID().uuidString)", isDirectory: true)
    }
}
