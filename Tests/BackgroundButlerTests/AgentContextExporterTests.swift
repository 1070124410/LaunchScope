import XCTest
@testable import BackgroundButler

final class AgentContextExporterTests: XCTestCase {
    func testRecognitionRequestOmitsArgumentsAndRuntimeIdentifiers() throws {
        let item = LaunchItem(
            label: "com.example.secret-worker",
            domain: .user,
            plistPath: "/Users/test/Library/LaunchAgents/com.example.secret-worker.plist",
            program: "/Users/test/bin/worker",
            arguments: ["/Users/test/bin/worker", "--token", "do-not-export"],
            runAtLoad: true,
            keepAlive: false,
            schedule: nil,
            status: .running,
            pid: 42,
            lastExitCode: 0,
            usage: nil,
            purpose: PurposeInfo(name: "Unknown", summary: "Unknown", vendor: "Unknown", category: "Unknown", confidence: .unknown)
        )

        let output = AgentContextExporter.recognitionRequest(for: item, homeDirectory: "/Users/test")

        XCTAssertTrue(output.contains("com.example.secret-worker"))
        XCTAssertTrue(output.contains("$HOME/bin/worker"))
        XCTAssertFalse(output.contains("do-not-export"))
        XCTAssertFalse(output.contains("--token"))
        XCTAssertFalse(output.contains("\"pid\""))
    }
}
