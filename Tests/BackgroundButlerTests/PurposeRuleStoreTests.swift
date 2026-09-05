import Foundation
import XCTest
@testable import BackgroundButler

final class PurposeRuleStoreTests: XCTestCase {
    func testLoadsVersionedRulePackAndRejectsInvalidRules() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let json = """
        {
          "schemaVersion": 1,
          "rules": [
            {
              "id": "com.example.worker",
              "labels": ["com.example.worker"],
              "name": "Example Worker",
              "summary": "Runs background work.",
              "vendor": "Example",
              "category": "Development"
            },
            {
              "id": "invalid",
              "name": "Invalid",
              "summary": "Missing selector.",
              "vendor": "Example",
              "category": "Development"
            }
          ]
        }
        """
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = PurposeRuleStore.inspect(from: url)

        XCTAssertEqual(result.rules.count, 1)
        XCTAssertEqual(result.rules.first?.id, "com.example.worker")
        XCTAssertTrue(result.issues.contains { $0.severity == .error && $0.ruleID == "invalid" })
    }

    func testLegacyArrayRemainsReadableWithWarning() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }

        let legacy = """
        [{"match":["example"],"name":"Example","summary":"Legacy rule.","vendor":"Example","category":"Development"}]
        """
        try Data(legacy.utf8).write(to: url)
        let result = PurposeRuleStore.inspect(from: url)

        XCTAssertEqual(result.rules.count, 1)
        XCTAssertTrue(result.issues.contains { $0.message.contains("旧版") })
    }

    func testVersionedRuleRejectsUnstableIDAndEmptyEvidence() throws {
        let rule = PurposeRule(
            id: "bad id",
            labels: ["com.example.worker"],
            name: "Example",
            summary: "Background work.",
            vendor: "Example",
            category: "Development",
            evidence: ""
        )

        let result = PurposeRuleStore.validate([rule], requireIDs: true)

        XCTAssertTrue(result.rules.isEmpty)
        XCTAssertTrue(result.issues.contains { $0.message.contains("id 只能") && $0.message.contains("evidence") })
    }

    func testImportPlanShowsChangesAndInstallCreatesBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = directory.appendingPathComponent("purpose-rules.json")
        let candidate = directory.appendingPathComponent("candidate.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = """
        {"schemaVersion":1,"rules":[
          {"id":"com.example.worker","labels":["com.example.worker"],"name":"Old Worker","summary":"Old purpose.","vendor":"Example","category":"Development"},
          {"id":"com.example.keep","labels":["com.example.keep"],"name":"Keep","summary":"Keep purpose.","vendor":"Example","category":"Development"}
        ]}
        """
        let incoming = """
        {"schemaVersion":1,"rules":[
          {"id":"com.example.worker","labels":["com.example.worker"],"name":"New Worker","summary":"New purpose.","vendor":"Example","category":"Development"},
          {"id":"com.example.added","labels":["com.example.added"],"name":"Added","summary":"Added purpose.","vendor":"Example","category":"Development"}
        ]}
        """
        try Data(original.utf8).write(to: target)
        try Data(incoming.utf8).write(to: candidate)

        let plan = PurposeRuleStore.planImport(from: candidate, targetURL: target)
        XCTAssertTrue(plan.canInstall)
        XCTAssertEqual(plan.added.map(\.id), ["com.example.added"])
        XCTAssertEqual(plan.updated.map(\.id), ["com.example.worker"])
        XCTAssertEqual(plan.mergedRules.count, 3)

        let installed = try PurposeRuleStore.install(plan)
        let loaded = PurposeRuleStore.inspect(from: target)
        XCTAssertEqual(installed.ruleCount, 3)
        XCTAssertNotNil(installed.backupURL)
        XCTAssertEqual(loaded.rules.first { $0.id == "com.example.worker" }?.name, "New Worker")

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any])
        let encodedRules = try XCTUnwrap(object["rules"] as? [[String: Any]])
        let worker = try XCTUnwrap(encodedRules.first { $0["id"] as? String == "com.example.worker" })
        XCTAssertNil(worker["match"], "Empty selectors must be omitted so the output still satisfies the JSON Schema.")
        XCTAssertNil(worker["programPrefixes"])
    }

    func testInstallRefusesTargetChangedAfterPreview() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = directory.appendingPathComponent("purpose-rules.json")
        let candidate = directory.appendingPathComponent("candidate.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let incoming = """
        {"schemaVersion":1,"rules":[{"id":"com.example.worker","labels":["com.example.worker"],"name":"Worker","summary":"Purpose.","vendor":"Example","category":"Development"}]}
        """
        try Data(incoming.utf8).write(to: candidate)
        let plan = PurposeRuleStore.planImport(from: candidate, targetURL: target)
        try Data("changed".utf8).write(to: target)

        XCTAssertThrowsError(try PurposeRuleStore.install(plan)) { error in
            guard case PurposeRuleImportError.targetChanged = error else {
                return XCTFail("Expected targetChanged, got \(error)")
            }
        }
    }
}
