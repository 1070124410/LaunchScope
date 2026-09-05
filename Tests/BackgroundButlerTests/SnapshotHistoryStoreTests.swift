import Foundation
import XCTest
@testable import BackgroundButler

final class SnapshotHistoryStoreTests: XCTestCase {
    func testFirstSnapshotEstablishesBaselineWithoutReportingEveryItemAsAdded() async throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = SnapshotHistoryStore(fileURL: location.file)

        let history = try await store.record(snapshot([fixtureItem()]))

        XCTAssertTrue(history.didEstablishBaseline)
        XCTAssertTrue(history.changes.isEmpty)
        XCTAssertEqual(history.baselineDate, Date(timeIntervalSince1970: 1_000))
    }

    func testDetectsAddedRemovedConfigurationAndStatusChanges() async throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = SnapshotHistoryStore(fileURL: location.file)
        let original = fixtureItem(status: .stopped)
        _ = try await store.record(snapshot([original], date: 1_000))

        let changed = fixtureItem(status: .running, keepAlive: true, program: "/opt/tools/new-helper")
        let added = fixtureItem(label: "com.example.new", name: "新后台项")
        let second = try await store.record(snapshot([changed, added], date: 2_000))
        XCTAssertEqual(Set(second.changes.map(\.kind)), [.added, .configuration, .status])
        XCTAssertTrue(second.changes.contains { $0.kind == .status && $0.summary == "已停止 → 运行中" })

        let third = try await store.record(snapshot([changed], date: 3_000))
        XCTAssertTrue(third.changes.contains { $0.itemID == added.id && $0.kind == .removed })
    }

    func testPersistedHistoryOmitsProgramPathArgumentsAndRuntimeIdentifiers() async throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let store = SnapshotHistoryStore(fileURL: location.file)
        let item = fixtureItem(program: "/Users/alice/Private/tool", arguments: ["--token", "secret-value"])

        _ = try await store.record(snapshot([item]))
        let text = try String(contentsOf: location.file, encoding: .utf8)

        XCTAssertFalse(text.contains("/Users/alice/Private/tool"))
        XCTAssertFalse(text.contains("secret-value"))
        XCTAssertFalse(text.contains("--token"))
        XCTAssertFalse(text.contains("4242"))
    }

    func testHistoryCanBeLoadedByANewStoreInstance() async throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        let firstStore = SnapshotHistoryStore(fileURL: location.file)
        _ = try await firstStore.record(snapshot([fixtureItem()], date: 1_000))
        _ = try await firstStore.record(snapshot([fixtureItem(status: .running)], date: 2_000))

        let reloaded = try await SnapshotHistoryStore(fileURL: location.file).current()

        XCTAssertEqual(reloaded.changes.count, 1)
        XCTAssertEqual(reloaded.changes.first?.kind, .status)
        XCTAssertEqual(reloaded.lastRecordedAt, Date(timeIntervalSince1970: 2_000))
    }

    func testNewerSchemaIsNotOverwritten() async throws {
        let location = temporaryLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let futureFile = #"{"schemaVersion":2,"futureData":"keep-me"}"#
        try Data(futureFile.utf8).write(to: location.file)
        let store = SnapshotHistoryStore(fileURL: location.file)

        do {
            _ = try await store.record(snapshot([fixtureItem()]))
            XCTFail("A newer schema must stop the write.")
        } catch let error as SnapshotHistoryError {
            guard case .unsupportedSchema(2) = error else {
                return XCTFail("Unexpected history error: \(error)")
            }
        }

        XCTAssertEqual(try String(contentsOf: location.file, encoding: .utf8), futureFile)
    }

    private func snapshot(_ items: [LaunchItem], date: TimeInterval = 1_000) -> ServiceSnapshot {
        ServiceSnapshot(items: items, generatedAt: Date(timeIntervalSince1970: date))
    }

    private func fixtureItem(
        label: String = "com.example.helper",
        name: String = "示例后台项",
        status: ItemStatus = .stopped,
        keepAlive: Bool = false,
        program: String = "/opt/tools/helper",
        arguments: [String] = []
    ) -> LaunchItem {
        LaunchItem(
            label: label,
            domain: .user,
            plistPath: "/Users/alice/Library/LaunchAgents/\(label).plist",
            program: program,
            arguments: [program] + arguments,
            runAtLoad: true,
            keepAlive: keepAlive,
            schedule: nil,
            status: status,
            pid: 4242,
            lastExitCode: nil,
            usage: ProcessUsage(cpuPercent: 1, memoryPercent: 2, residentMemoryMB: 3),
            purpose: PurposeInfo(
                name: name,
                summary: "测试用途",
                vendor: "Example",
                category: "测试",
                confidence: .exact
            )
        )
    }

    private func temporaryLocation() -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchScopeHistoryTests-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent("snapshot-history.json"))
    }
}
