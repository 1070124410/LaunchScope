import XCTest
@testable import BackgroundButler

final class PurposeCatalogTests: XCTestCase {
    func testKnownServiceGetsExactDescription() {
        let info = PurposeCatalog.lookup(
            label: "homebrew.mxcl.mysql",
            program: "/opt/homebrew/opt/mysql/bin/mysqld",
            arguments: []
        )
        XCTAssertEqual(info.name, "MySQL 数据库")
        XCTAssertEqual(info.confidence, .exact)
    }

    func testApplicationPathIsMarkedAsInference() {
        let info = PurposeCatalog.lookup(
            label: "example.helper",
            program: "/Applications/Example.app/Contents/MacOS/helper",
            arguments: []
        )
        XCTAssertEqual(info.confidence, .inferred)
        XCTAssertEqual(info.name, "Example")
    }

    func testUnknownItemDoesNotPretendToBeKnown() {
        let info = PurposeCatalog.lookup(label: "org.unknown.worker", program: "/tmp/worker", arguments: [])
        XCTAssertEqual(info.confidence, .unknown)
        XCTAssertTrue(info.summary.contains("无法"))
    }

    func testCustomRuleOverridesBuiltInCatalog() {
        let catalog = PurposeCatalog(customRules: [
            PurposeRule(
                match: ["mysql"],
                name: "团队测试数据库",
                summary: "供本地集成测试使用。",
                vendor: "My Team",
                category: "测试设施"
            )
        ])

        let info = catalog.resolve(label: "homebrew.mxcl.mysql", program: "/opt/homebrew/bin/mysqld", arguments: [])
        XCTAssertEqual(info.name, "团队测试数据库")
        XCTAssertEqual(info.category, "测试设施")
        XCTAssertEqual(info.confidence, .exact)
    }

    func testExactLabelDoesNotMatchSimilarLabel() {
        let catalog = PurposeCatalog(customRules: [
            PurposeRule(
                id: "com.example.worker",
                labels: ["com.example.worker"],
                name: "Example Worker",
                summary: "Runs Example background work.",
                vendor: "Example",
                category: "Development",
                evidence: "Example documentation",
                disableImpact: "Background work stops."
            )
        ])

        XCTAssertEqual(catalog.resolve(label: "com.example.worker", program: "", arguments: []).name, "Example Worker")
        XCTAssertEqual(catalog.resolve(label: "com.example.worker.beta", program: "", arguments: []).confidence, .unknown)
    }
}
