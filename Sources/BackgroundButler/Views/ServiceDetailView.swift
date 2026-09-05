import AppKit
import SwiftUI

struct ServiceDetailView: View {
    @EnvironmentObject private var store: AppStore
    let item: LaunchItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                attentionBanner
                purposeSection
                if item.usage != nil { resourceSection }
                startupSection
                evidenceSection
                if item.purpose.confidence != .exact { ruleHint }
            }
            .padding(26)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(item.purpose.name)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: item.status.icon)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 54, height: 54)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.purpose.name).font(.title.bold())
                HStack(spacing: 7) {
                    StatusBadge(text: item.status.title, icon: item.status.icon, tint: statusColor)
                    StatusBadge(text: item.purpose.confidence.title, icon: confidenceIcon, tint: confidenceColor)
                    StatusBadge(text: item.sourceTitle, icon: "shippingbox", tint: .secondary)
                }
                Text(item.label)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var attentionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.attentionLevel.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.attentionLevel.title).fontWeight(.semibold)
                Text(item.attentionReason).font(.callout)
            }
            Spacer()
        }
        .foregroundStyle(attentionColor)
        .padding(13)
        .background(attentionColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var purposeSection: some View {
        SurfaceCard(title: "用途与来源", icon: "lightbulb.max") {
            Text(item.purpose.summary).fixedSize(horizontal: false, vertical: true)
            Divider()
            DetailLine(title: "开发者或来源", value: item.purpose.vendor)
            DetailLine(title: "类别", value: item.purpose.category)
            DetailLine(title: "影响范围", value: item.domain.title)
            DetailLine(title: "识别依据", value: item.purpose.confidence.title)
            if let ruleID = item.purpose.ruleID { DetailLine(title: "规则 ID", value: ruleID) }
            if let evidence = item.purpose.evidence { DetailLine(title: "核验来源", value: evidence) }
            if let impact = item.purpose.disableImpact { DetailLine(title: "禁用影响", value: impact) }
        }
    }

    private var resourceSection: some View {
        SurfaceCard(title: "当前资源", icon: "gauge.with.dots.needle.67percent") {
            if let usage = item.usage {
                HStack(spacing: 34) {
                    MetricValue(value: String(format: "%.1f%%", usage.cpuPercent), label: "CPU")
                    MetricValue(value: String(format: "%.0f MB", usage.residentMemoryMB), label: "常驻内存")
                    MetricValue(value: item.pid.map(String.init) ?? "—", label: "PID")
                }
            }
        }
    }

    private var startupSection: some View {
        SurfaceCard(title: "启动行为", icon: "power") {
            DetailLine(title: "登录后启动", value: item.runAtLoad ? "是" : "否")
            DetailLine(title: "退出后自动重启", value: item.keepAlive ? "是" : "否")
            if let schedule = item.schedule { DetailLine(title: "定时计划", value: schedule) }
            DetailLine(title: "当前状态", value: item.status.title)
            if let code = item.lastExitCode { DetailLine(title: "最近退出码", value: String(code)) }
        }
    }

    private var evidenceSection: some View {
        SurfaceCard(title: "原始证据", icon: "terminal") {
            EvidenceBlock(title: "可执行文件", value: item.program.isEmpty ? "未从运行信息中获得" : item.program)
            if !item.commandLine.isEmpty { EvidenceBlock(title: "完整命令", value: item.commandLine) }
            EvidenceBlock(title: "配置来源", value: item.plistPath ?? "由应用动态注册，没有独立 plist 文件")
            HStack {
                Button("复制 Label", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.label, forType: .string)
                }
                if let path = item.plistPath {
                    Button("在 Finder 中显示", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var ruleHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.badge.plus").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("可以补充本地识别规则").fontWeight(.semibold)
                Text("复制隐私受限的上下文，让 AI 按 Rule Pack v1 生成候选规则；写入前仍需校验和人工确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("复制给 AI 识别", systemImage: "sparkles") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AgentContextExporter.recognitionRequest(for: item), forType: .string)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if item.status == .disabled {
                Button("启用", systemImage: "checkmark.circle") { store.request(.enable, item: item) }
                    .buttonStyle(.borderedProminent)
            } else {
                if item.status == .running {
                    Button("临时停止", systemImage: "stop.circle") { store.request(.stop, item: item) }
                        .buttonStyle(.bordered)
                } else if item.plistPath != nil {
                    Button("启动", systemImage: "play.circle") { store.request(.start, item: item) }
                        .buttonStyle(.bordered)
                }
                Button("禁用", systemImage: "nosign") { store.request(.disable, item: item) }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            Spacer()
            Label("不删除应用或数据", systemImage: "externaldrive.badge.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var statusColor: Color {
        switch item.status {
        case .running: .green
        case .scheduled: .blue
        case .failed: .red
        case .disabled, .stopped: .secondary
        }
    }

    private var confidenceIcon: String {
        switch item.purpose.confidence {
        case .exact: "checkmark.seal"
        case .inferred: "arrow.triangle.branch"
        case .unknown: "questionmark.diamond"
        }
    }

    private var confidenceColor: Color { item.purpose.confidence == .exact ? .green : .orange }
    private var attentionColor: Color {
        switch item.attentionLevel {
        case .normal: .green
        case .notice: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}
