import Foundation

enum LaunchDomain: String, Codable, Sendable {
    case user
    case system

    var title: String { self == .user ? "当前用户" : "整台 Mac" }
    var icon: String { self == .user ? "person.crop.circle" : "desktopcomputer" }
}

enum ItemStatus: String, Codable, Sendable {
    case running
    case stopped
    case scheduled
    case disabled
    case failed

    var title: String {
        switch self {
        case .running: "运行中"
        case .stopped: "已停止"
        case .scheduled: "等待触发"
        case .disabled: "已禁用"
        case .failed: "需要关注"
        }
    }

    var icon: String {
        switch self {
        case .running: "play.fill"
        case .stopped: "stop.fill"
        case .scheduled: "clock.fill"
        case .disabled: "nosign"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

enum PurposeConfidence: String, Codable, Sendable {
    case exact
    case inferred
    case unknown

    var title: String {
        switch self {
        case .exact: "已识别"
        case .inferred: "根据路径推断"
        case .unknown: "用途未知"
        }
    }
}

enum AttentionLevel: Int, Codable, Comparable, Sendable {
    case normal = 0
    case notice = 1
    case warning = 2
    case critical = 3

    static func < (lhs: AttentionLevel, rhs: AttentionLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .normal: "状态正常"
        case .notice: "建议了解"
        case .warning: "需要关注"
        case .critical: "运行异常"
        }
    }

    var icon: String {
        switch self {
        case .normal: "checkmark.circle"
        case .notice: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }
}

struct PurposeInfo: Hashable, Codable, Sendable {
    let name: String
    let summary: String
    let vendor: String
    let category: String
    let confidence: PurposeConfidence
    let ruleID: String?
    let evidence: String?
    let disableImpact: String?

    init(
        name: String,
        summary: String,
        vendor: String,
        category: String,
        confidence: PurposeConfidence,
        ruleID: String? = nil,
        evidence: String? = nil,
        disableImpact: String? = nil
    ) {
        self.name = name
        self.summary = summary
        self.vendor = vendor
        self.category = category
        self.confidence = confidence
        self.ruleID = ruleID
        self.evidence = evidence
        self.disableImpact = disableImpact
    }
}

struct ProcessUsage: Hashable, Codable, Sendable {
    let cpuPercent: Double
    let memoryPercent: Double
    let residentMemoryMB: Double
}

struct LaunchItem: Identifiable, Hashable, Codable, Sendable {
    var id: String { "\(domain.rawValue):\(label)" }

    let label: String
    let domain: LaunchDomain
    let plistPath: String?
    let program: String
    let arguments: [String]
    let runAtLoad: Bool
    let keepAlive: Bool
    let schedule: String?
    let status: ItemStatus
    let pid: Int?
    let lastExitCode: Int?
    let usage: ProcessUsage?
    let purpose: PurposeInfo

    var commandLine: String {
        ([program] + arguments.dropFirst(program == arguments.first ? 1 : 0)).filter { !$0.isEmpty }.joined(separator: " ")
    }

    var isDynamic: Bool { plistPath == nil }
    var needsAttention: Bool { status == .failed || (lastExitCode != nil && lastExitCode != 0 && status != .disabled) }

    var sourceTitle: String {
        guard let plistPath else { return "应用动态注册" }
        if plistPath.hasPrefix("/Library/LaunchDaemons") { return "系统 LaunchDaemon" }
        if plistPath.hasPrefix("/Library/LaunchAgents") { return "系统 LaunchAgent" }
        return "用户 LaunchAgent"
    }

    var attentionLevel: AttentionLevel {
        if status == .failed { return .critical }
        if needsAttention { return .warning }
        if purpose.confidence == .unknown && status == .running { return .warning }
        if domain == .system || keepAlive || purpose.confidence != .exact { return .notice }
        return .normal
    }

    var attentionReason: String {
        if status == .failed { return "该任务曾多次退出，当前状态异常。" }
        if needsAttention { return "最近退出码不是 0，需要结合日志确认原因。" }
        if purpose.confidence == .unknown && status == .running { return "用途尚未识别，但当前正在运行。" }
        if domain == .system { return "它影响整台 Mac，管理时需要管理员授权。" }
        if keepAlive { return "它配置为退出后自动重启。" }
        if purpose.confidence == .inferred { return "用途来自路径推断，尚未由明确规则确认。" }
        return "未发现需要特别处理的信号。"
    }
}

enum SidebarFilter: String, CaseIterable, Identifiable {
    case overview
    case aiIntegration
    case all
    case running
    case disabled
    case scheduled
    case attention
    case unknown
    case system

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "总览"
        case .aiIntegration: "AI 助手"
        case .all: "全部后台项"
        case .running: "正在运行"
        case .disabled: "已禁用"
        case .scheduled: "定时任务"
        case .attention: "需要关注"
        case .unknown: "用途未知"
        case .system: "整台 Mac"
        }
    }
    var icon: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .aiIntegration: "cpu"
        case .all: "square.stack.3d.up"
        case .running: "play.circle"
        case .disabled: "nosign"
        case .scheduled: "calendar.badge.clock"
        case .attention: "exclamationmark.triangle"
        case .unknown: "questionmark.diamond"
        case .system: "desktopcomputer"
        }
    }
}

enum ServiceSort: String, CaseIterable, Identifiable {
    case status
    case name
    case cpu

    var id: String { rawValue }
    var title: String {
        switch self {
        case .status: "按状态"
        case .name: "按名称"
        case .cpu: "按 CPU"
        }
    }
}

struct ServiceStatistics: Sendable {
    let total: Int
    let running: Int
    let disabled: Int
    let scheduled: Int
    let attention: Int
    let unknown: Int
    let system: Int
    let recognizedPercent: Int
    let residentMemoryMB: Double
}

struct ServiceSnapshot: Sendable {
    let items: [LaunchItem]
    let generatedAt: Date

    var statistics: ServiceStatistics {
        let recognized = items.count { $0.purpose.confidence != .unknown }
        return ServiceStatistics(
            total: items.count,
            running: items.count { $0.status == .running },
            disabled: items.count { $0.status == .disabled },
            scheduled: items.count { $0.schedule != nil },
            attention: items.count { $0.needsAttention || ($0.purpose.confidence == .unknown && $0.status == .running) },
            unknown: items.count { $0.purpose.confidence == .unknown },
            system: items.count { $0.domain == .system },
            recognizedPercent: items.isEmpty ? 100 : Int((Double(recognized) / Double(items.count) * 100).rounded()),
            residentMemoryMB: items.compactMap(\.usage?.residentMemoryMB).reduce(0, +)
        )
    }
}
