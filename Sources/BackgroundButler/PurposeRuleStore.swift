import CryptoKit
import Darwin
import Foundation

enum PurposeRuleIssueSeverity: String, Sendable {
    case warning
    case error
}

struct PurposeRuleIssue: Sendable, Equatable {
    let severity: PurposeRuleIssueSeverity
    let ruleID: String?
    let message: String
}

enum PurposeRuleFormat: Sendable {
    case missing
    case invalid
    case legacy
    case versioned(Int)

    var title: String {
        switch self {
        case .missing: "尚未创建"
        case .invalid: "格式无效"
        case .legacy: "旧版数组格式"
        case .versioned(let version): "Rule Pack v\(version)"
        }
    }
}

struct PurposeRuleLoadResult: Sendable {
    let rules: [PurposeRule]
    let issues: [PurposeRuleIssue]
    let sourceURL: URL
    let format: PurposeRuleFormat
}

struct PurposeRuleImportPlan: Identifiable, Sendable {
    let id = UUID()
    let candidateURL: URL
    let targetURL: URL
    let added: [PurposeRule]
    let updated: [PurposeRule]
    let unchanged: [PurposeRule]
    let mergedRules: [PurposeRule]
    let issues: [PurposeRuleIssue]
    let originalTargetData: Data?

    var canInstall: Bool {
        (!added.isEmpty || !updated.isEmpty) && !issues.contains { $0.severity == .error }
    }
}

struct PurposeRuleInstallResult: Sendable {
    let targetURL: URL
    let backupURL: URL?
    let ruleCount: Int
}

enum PurposeRuleImportError: LocalizedError {
    case targetChanged
    case invalidPlan

    var errorDescription: String? {
        switch self {
        case .targetChanged: "规则文件在预览后已被其他操作修改。请重新导入并核对差异。"
        case .invalidPlan: "候选规则存在错误，不能安装。"
        }
    }
}

private struct PurposeRulePack: Codable {
    let schemaVersion: Int
    let rules: [PurposeRule]
}

enum PurposeRuleStore {
    static let supportedSchemaVersion = 1

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LaunchScope", isDirectory: true)
    }

    static var rulesURL: URL { directoryURL.appendingPathComponent("purpose-rules.json") }

    private static var legacyRulesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BackgroundButler/purpose-rules.json")
    }

    static func load(from url: URL = rulesURL) -> [PurposeRule] {
        inspect(from: url).rules
    }

    static func inspect(from url: URL = rulesURL) -> PurposeRuleLoadResult {
        let shouldUseLegacy = url.standardizedFileURL == rulesURL.standardizedFileURL
            && !FileManager.default.fileExists(atPath: url.path)
            && FileManager.default.fileExists(atPath: legacyRulesURL.path)
        let sourceURL = shouldUseLegacy ? legacyRulesURL : url
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return PurposeRuleLoadResult(rules: [], issues: [], sourceURL: url, format: .missing)
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            return failedResult(sourceURL: sourceURL, message: "无法读取规则文件：\(error.localizedDescription)")
        }

        let decoder = JSONDecoder()
        if let pack = try? decoder.decode(PurposeRulePack.self, from: data) {
            guard pack.schemaVersion == supportedSchemaVersion else {
                return PurposeRuleLoadResult(
                    rules: [],
                    issues: [PurposeRuleIssue(severity: .error, ruleID: nil, message: "不支持 schemaVersion \(pack.schemaVersion)，当前只支持 v\(supportedSchemaVersion)。")],
                    sourceURL: sourceURL,
                    format: .versioned(pack.schemaVersion)
                )
            }
            let validated = validate(pack.rules, requireIDs: true)
            return PurposeRuleLoadResult(rules: validated.rules, issues: validated.issues, sourceURL: sourceURL, format: .versioned(pack.schemaVersion))
        }

        if let rules = try? decoder.decode([PurposeRule].self, from: data) {
            var validated = validate(rules, requireIDs: false)
            validated.issues.insert(
                PurposeRuleIssue(severity: .warning, ruleID: nil, message: "旧版数组格式仍可读取；建议迁移到带 schemaVersion 的 Rule Pack v1。"),
                at: 0
            )
            return PurposeRuleLoadResult(rules: validated.rules, issues: validated.issues, sourceURL: sourceURL, format: .legacy)
        }

        do {
            _ = try decoder.decode(PurposeRulePack.self, from: data)
            return failedResult(sourceURL: sourceURL, message: "规则文件格式无效。")
        } catch {
            return failedResult(sourceURL: sourceURL, message: "JSON 无法解析：\(error.localizedDescription)")
        }
    }

    static func planImport(from candidateURL: URL, targetURL: URL = rulesURL) -> PurposeRuleImportPlan {
        let candidateResult = inspect(from: candidateURL)
        let targetResult = inspect(from: targetURL)
        var issues = candidateResult.issues.map {
            PurposeRuleIssue(severity: $0.severity, ruleID: $0.ruleID, message: "候选文件：\($0.message)")
        }
        issues += targetResult.issues.map {
            PurposeRuleIssue(severity: $0.severity, ruleID: $0.ruleID, message: "现有规则：\($0.message)")
        }
        if case .legacy = candidateResult.format {
            issues.append(PurposeRuleIssue(severity: .error, ruleID: nil, message: "候选文件必须使用 Rule Pack v1；旧版数组只作为现有配置兼容读取。"))
        }
        if case .missing = candidateResult.format {
            issues.append(PurposeRuleIssue(severity: .error, ruleID: nil, message: "候选文件不存在或不可读取。"))
        }
        if candidateResult.rules.isEmpty && !issues.contains(where: { $0.severity == .error }) {
            issues.append(PurposeRuleIssue(severity: .error, ruleID: nil, message: "候选 Rule Pack 至少需要一条有效规则。"))
        }

        let normalizedExisting = validate(targetResult.rules.map(addingLegacyID), requireIDs: true)
        issues += normalizedExisting.issues.filter { $0.severity == .error }.map {
            PurposeRuleIssue(severity: $0.severity, ruleID: $0.ruleID, message: "现有规则迁移：\($0.message)")
        }
        let existing = normalizedExisting.rules
        let candidate = candidateResult.rules
        var existingByID: [String: PurposeRule] = [:]
        for rule in existing {
            if let id = rule.id { existingByID[id] = rule }
        }
        let added = candidate.filter { rule in
            guard let id = rule.id else { return false }
            return existingByID[id] == nil
        }
        let updated = candidate.filter { rule in
            guard let id = rule.id, let current = existingByID[id] else { return false }
            return current != rule
        }
        let unchanged = candidate.filter { rule in
            guard let id = rule.id, let current = existingByID[id] else { return false }
            return current == rule
        }
        if added.isEmpty && updated.isEmpty && !candidate.isEmpty && !issues.contains(where: { $0.severity == .error }) {
            issues.append(PurposeRuleIssue(severity: .warning, ruleID: nil, message: "候选规则与现有配置相同，没有需要安装的变化。"))
        }

        var candidateByID = Dictionary(uniqueKeysWithValues: candidate.compactMap { rule in
            rule.id.map { ($0, rule) }
        })
        var merged = existing.map { current in
            guard let id = current.id, let replacement = candidateByID.removeValue(forKey: id) else { return current }
            return replacement
        }
        merged += candidate.compactMap { rule in
            guard let id = rule.id else { return nil }
            return candidateByID[id]
        }

        return PurposeRuleImportPlan(
            candidateURL: candidateURL,
            targetURL: targetURL,
            added: added,
            updated: updated,
            unchanged: unchanged,
            mergedRules: merged,
            issues: issues,
            originalTargetData: try? Data(contentsOf: targetURL)
        )
    }

    static func install(_ plan: PurposeRuleImportPlan) throws -> PurposeRuleInstallResult {
        guard plan.canInstall else { throw PurposeRuleImportError.invalidPlan }

        let validated = validate(plan.mergedRules, requireIDs: true)
        guard !validated.rules.isEmpty, !validated.issues.contains(where: { $0.severity == .error }) else {
            throw PurposeRuleImportError.invalidPlan
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: plan.targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(PurposeRulePack(schemaVersion: supportedSchemaVersion, rules: validated.rules)) + Data("\n".utf8)
        let temporaryURL = plan.targetURL.deletingLastPathComponent()
            .appendingPathComponent(".purpose-rules-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)

        let currentData = try? Data(contentsOf: plan.targetURL)
        guard currentData == plan.originalTargetData else { throw PurposeRuleImportError.targetChanged }

        var backupURL: URL?
        if fileManager.fileExists(atPath: plan.targetURL.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
            let suffix = UUID().uuidString.prefix(8)
            let backup = plan.targetURL.appendingPathExtension("backup-\(formatter.string(from: Date()))-\(suffix)")
            try fileManager.copyItem(at: plan.targetURL, to: backup)
            backupURL = backup
        }

        guard Darwin.rename(temporaryURL.path, plan.targetURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return PurposeRuleInstallResult(targetURL: plan.targetURL, backupURL: backupURL, ruleCount: validated.rules.count)
    }

    static func validate(_ rules: [PurposeRule], requireIDs: Bool) -> (rules: [PurposeRule], issues: [PurposeRuleIssue]) {
        var accepted: [PurposeRule] = []
        var issues: [PurposeRuleIssue] = []
        var seenIDs = Set<String>()

        for (index, rule) in rules.enumerated() {
            let displayID = rule.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            var errors: [String] = []
            if requireIDs && (displayID?.isEmpty != false) { errors.append("缺少非空 id") }
            if let displayID, !displayID.isEmpty,
               displayID.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) == nil {
                errors.append("id 只能包含字母、数字、点、下划线和连字符")
            }
            if let displayID, !displayID.isEmpty && !seenIDs.insert(displayID).inserted { errors.append("id 重复") }
            if rule.labels.isEmpty && rule.programPrefixes.isEmpty && rule.match.isEmpty { errors.append("至少需要 labels、programPrefixes 或 match 中的一个匹配条件") }
            if rule.labels.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { errors.append("labels 不能包含空值") }
            if rule.programPrefixes.contains(where: { !$0.hasPrefix("/") }) { errors.append("programPrefixes 必须是绝对路径前缀") }
            if rule.match.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { errors.append("match 不能包含空值") }
            if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("name 不能为空") }
            if rule.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("summary 不能为空") }
            if rule.vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("vendor 不能为空") }
            if rule.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("category 不能为空") }
            if let evidence = rule.evidence, evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("evidence 存在时不能为空") }
            if let impact = rule.disableImpact, impact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("disableImpact 存在时不能为空") }

            if errors.isEmpty {
                accepted.append(rule)
                if !rule.match.isEmpty {
                    issues.append(PurposeRuleIssue(severity: .warning, ruleID: displayID, message: "规则 \(displayID ?? "#\(index + 1)") 使用宽泛的 match 包含匹配；优先使用精确 labels。"))
                }
            } else {
                issues.append(PurposeRuleIssue(severity: .error, ruleID: displayID, message: "规则 \(displayID ?? "#\(index + 1)")：\(errors.joined(separator: "；"))。"))
            }
        }
        return (accepted, issues)
    }

    private static func failedResult(sourceURL: URL, message: String) -> PurposeRuleLoadResult {
        PurposeRuleLoadResult(
            rules: [],
            issues: [PurposeRuleIssue(severity: .error, ruleID: nil, message: message)],
            sourceURL: sourceURL,
            format: .invalid
        )
    }

    private static func addingLegacyID(_ rule: PurposeRule) -> PurposeRule {
        guard rule.id == nil else { return rule }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(rule)) ?? Data(rule.name.utf8)
        let digest = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        return PurposeRule(
            id: "legacy.\(digest)",
            labels: rule.labels,
            programPrefixes: rule.programPrefixes,
            match: rule.match,
            name: rule.name,
            summary: rule.summary,
            vendor: rule.vendor,
            category: rule.category,
            evidence: rule.evidence,
            disableImpact: rule.disableImpact
        )
    }

    static let exampleJSON = """
    {
      "schemaVersion": 1,
      "rules": [
        {
          "id": "com.example.worker",
          "labels": ["com.example.worker"],
          "name": "示例后台服务",
          "summary": "为 Example 提供后台同步。",
          "vendor": "Example",
          "category": "效率工具",
          "evidence": "Example 官方帮助文档与已安装 plist",
          "disableImpact": "自动同步会停止，手动打开应用仍可使用。"
        }
      ]
    }
    """
}
