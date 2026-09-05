import CryptoKit
import Foundation

enum SnapshotHistoryError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "历史文件版本 \(version) 高于当前应用支持范围，已停止写入以保护数据。"
        }
    }
}

enum SnapshotChangeKind: String, Codable, Sendable {
    case added
    case removed
    case configuration
    case status

    var title: String {
        switch self {
        case .added: "新增"
        case .removed: "移除"
        case .configuration: "配置变化"
        case .status: "状态变化"
        }
    }

    var icon: String {
        switch self {
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .configuration: "slider.horizontal.3"
        case .status: "arrow.triangle.2.circlepath"
        }
    }
}

struct SnapshotChange: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let itemID: String
    let itemName: String
    let kind: SnapshotChangeKind
    let summary: String
    let detail: String
    let occurredAt: Date
    let attentionLevel: AttentionLevel
}

struct SnapshotHistory: Sendable {
    let baselineDate: Date?
    let lastRecordedAt: Date?
    let changes: [SnapshotChange]
    let didEstablishBaseline: Bool

    static let empty = SnapshotHistory(
        baselineDate: nil,
        lastRecordedAt: nil,
        changes: [],
        didEstablishBaseline: false
    )
}

actor SnapshotHistoryStore {
    private static let schemaVersion = 1
    private let fileURL: URL
    private let retentionInterval: TimeInterval
    private let maximumChanges: Int

    init(
        fileURL: URL = SnapshotHistoryStore.defaultFileURL,
        retentionInterval: TimeInterval = 30 * 24 * 60 * 60,
        maximumChanges: Int = 200
    ) {
        self.fileURL = fileURL
        self.retentionInterval = retentionInterval
        self.maximumChanges = maximumChanges
    }

    func record(_ snapshot: ServiceSnapshot) throws -> SnapshotHistory {
        let previous = try loadFileIfPresent()
        let current = StoredSnapshot(snapshot)
        let didEstablishBaseline = previous == nil
        let newChanges = previous.map { changes(from: $0.latest, to: current) } ?? []
        let cutoff = snapshot.generatedAt.addingTimeInterval(-retentionInterval)
        let retained = (newChanges + (previous?.changes ?? []))
            .filter { $0.occurredAt >= cutoff }
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(maximumChanges)

        let file = StoredHistoryFile(
            schemaVersion: Self.schemaVersion,
            baselineDate: previous?.baselineDate ?? snapshot.generatedAt,
            latest: current,
            changes: Array(retained)
        )
        try persist(file)
        return SnapshotHistory(
            baselineDate: file.baselineDate,
            lastRecordedAt: snapshot.generatedAt,
            changes: file.changes,
            didEstablishBaseline: didEstablishBaseline
        )
    }

    func current() throws -> SnapshotHistory {
        guard let file = try loadFileIfPresent() else { return .empty }
        return SnapshotHistory(
            baselineDate: file.baselineDate,
            lastRecordedAt: file.latest.generatedAt,
            changes: file.changes,
            didEstablishBaseline: false
        )
    }

    private func changes(from previous: StoredSnapshot, to current: StoredSnapshot) -> [SnapshotChange] {
        let oldItems = Dictionary(uniqueKeysWithValues: previous.items.map { ($0.id, $0) })
        let newItems = Dictionary(uniqueKeysWithValues: current.items.map { ($0.id, $0) })
        var result: [SnapshotChange] = []

        for item in current.items where oldItems[item.id] == nil {
            result.append(change(
                item: item,
                kind: .added,
                summary: "发现新的后台项",
                detail: "首次出现在本机扫描结果中。请先核对用途与来源，再决定是否管理。",
                date: current.generatedAt,
                attention: item.status == .failed ? .critical : .notice
            ))
        }

        for item in previous.items where newItems[item.id] == nil {
            result.append(change(
                item: item,
                kind: .removed,
                summary: "后台项已不在扫描结果中",
                detail: "这可能来自卸载、取消注册或扫描范围变化；LaunchScope 没有据此执行删除。",
                date: current.generatedAt,
                attention: .normal
            ))
        }

        for item in current.items {
            guard let old = oldItems[item.id] else { continue }
            let changedFields = item.configurationChanges(comparedWith: old)
            if !changedFields.isEmpty {
                result.append(change(
                    item: item,
                    kind: .configuration,
                    summary: "启动配置发生变化",
                    detail: changedFields.joined(separator: "、") + "。LaunchScope 只记录变化，不会自动修改配置。",
                    date: current.generatedAt,
                    attention: .warning
                ))
            }
            if item.status != old.status {
                let level: AttentionLevel = item.status == .failed ? .critical : .notice
                result.append(change(
                    item: item,
                    kind: .status,
                    summary: "\(old.status.title) → \(item.status.title)",
                    detail: "这是两次本机快照之间观察到的状态变化，不代表 LaunchScope 执行了操作。",
                    date: current.generatedAt,
                    attention: level
                ))
            }
        }

        return result
    }

    private func change(
        item: StoredItem,
        kind: SnapshotChangeKind,
        summary: String,
        detail: String,
        date: Date,
        attention: AttentionLevel
    ) -> SnapshotChange {
        SnapshotChange(
            id: UUID(),
            itemID: item.id,
            itemName: item.name,
            kind: kind,
            summary: summary,
            detail: detail,
            occurredAt: date,
            attentionLevel: attention
        )
    }

    private func loadFileIfPresent() throws -> StoredHistoryFile? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(StoredHistoryHeader.self, from: data)
        guard header.schemaVersion == Self.schemaVersion else {
            throw SnapshotHistoryError.unsupportedSchema(header.schemaVersion)
        }
        return try decoder.decode(StoredHistoryFile.self, from: data)
    }

    private func persist(_ file: StoredHistoryFile) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LaunchScope", isDirectory: true)
            .appendingPathComponent("snapshot-history.json")
    }
}

private struct StoredHistoryFile: Codable {
    let schemaVersion: Int
    let baselineDate: Date
    let latest: StoredSnapshot
    let changes: [SnapshotChange]
}

private struct StoredHistoryHeader: Decodable {
    let schemaVersion: Int
}

private struct StoredSnapshot: Codable {
    let generatedAt: Date
    let items: [StoredItem]

    init(_ snapshot: ServiceSnapshot) {
        generatedAt = snapshot.generatedAt
        items = snapshot.items.map(StoredItem.init).sorted { $0.id < $1.id }
    }
}

private struct StoredItem: Codable {
    let id: String
    let name: String
    let status: ItemStatus
    let runAtLoad: Bool
    let keepAlive: Bool
    let schedule: String?
    let programFingerprint: String

    init(_ item: LaunchItem) {
        id = item.id
        name = item.purpose.name
        status = item.status
        runAtLoad = item.runAtLoad
        keepAlive = item.keepAlive
        schedule = item.schedule
        programFingerprint = Self.fingerprint(item.program)
    }

    func configurationChanges(comparedWith old: StoredItem) -> [String] {
        var changes: [String] = []
        if programFingerprint != old.programFingerprint { changes.append("可执行文件") }
        if runAtLoad != old.runAtLoad { changes.append("登录时加载") }
        if keepAlive != old.keepAlive { changes.append("自动保活") }
        if schedule != old.schedule { changes.append("触发计划") }
        return changes
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
