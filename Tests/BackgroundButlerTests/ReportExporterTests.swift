import XCTest
@testable import BackgroundButler

final class ReportExporterTests: XCTestCase {
    func testPublicReportIncludesSummaryButOmitsCommandAndArguments() {
        let item = LaunchItem(
            label: "com.example.worker",
            domain: .user,
            plistPath: "/Users/test/Library/LaunchAgents/com.example.worker.plist",
            program: "/Users/test/bin/worker",
            arguments: ["/Users/test/bin/worker", "--token", "do-not-export"],
            runAtLoad: true,
            keepAlive: false,
            schedule: nil,
            status: .running,
            pid: 42,
            lastExitCode: 0,
            usage: nil,
            purpose: PurposeInfo(
                name: "Example Worker",
                summary: "Example purpose",
                vendor: "Example",
                category: "Development",
                confidence: .exact
            )
        )

        let report = ReportExporter.markdown(snapshot: ServiceSnapshot(items: [item], generatedAt: Date(timeIntervalSince1970: 0)))

        XCTAssertTrue(report.contains("Example Worker"))
        XCTAssertTrue(report.contains("com.example.worker"))
        XCTAssertTrue(report.contains("识别率：100%"))
        XCTAssertFalse(report.contains("do-not-export"))
        XCTAssertFalse(report.contains("--token"))
        XCTAssertFalse(report.contains("/Users/test/bin/worker"))
    }
}
