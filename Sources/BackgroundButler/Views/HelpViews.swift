import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RulesHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var result = PurposeRuleStore.inspect()
    @State private var isImporting = false
    @State private var importPlan: PurposeRuleImportPlan?
    @State private var importMessage: String?
    @State private var importMessageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自定义识别规则").font(.title2.bold())
                    Text("让私有或小众服务显示成容易理解的名称。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("保存位置")
                .font(.headline)
            Text(PurposeRuleStore.rulesURL.path)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Label(result.format.title, systemImage: result.issues.contains(where: { $0.severity == .error }) ? "exclamationmark.triangle" : "checkmark.seal")
                    .font(.callout.weight(.semibold))
                Text("已载入 \(result.rules.count) 条有效规则")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !result.issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue.message, systemImage: issue.severity == .error ? "xmark.circle" : "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                    }
                }
            }
            if let importMessage {
                Label(importMessage, systemImage: importMessageIsError ? "xmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(importMessageIsError ? Color.red : Color.green)
                    .textSelection(.enabled)
            }
            Text("JSON 示例").font(.headline)
            ScrollView {
                Text(PurposeRuleStore.exampleJSON)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("导入 Rule Pack…", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                Button("复制示例", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(PurposeRuleStore.exampleJSON, forType: .string)
                }
                if FileManager.default.fileExists(atPath: PurposeRuleStore.directoryURL.path) {
                    Button("在 Finder 中打开", systemImage: "folder") {
                        NSWorkspace.shared.open(PurposeRuleStore.directoryURL)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 720, height: 660)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { selection in
            switch selection {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                importPlan = PurposeRuleStore.planImport(from: url)
                if accessed { url.stopAccessingSecurityScopedResource() }
            case .failure(let error):
                importMessage = "无法读取候选文件：\(error.localizedDescription)"
                importMessageIsError = true
            }
        }
        .sheet(item: $importPlan) { plan in
            RuleImportPreviewView(plan: plan) {
                do {
                    let installed = try PurposeRuleStore.install(plan)
                    result = PurposeRuleStore.inspect()
                    importMessage = if let backup = installed.backupURL {
                        "已安装 \(installed.ruleCount) 条规则；原文件备份到 \(backup.path)"
                    } else {
                        "已安装 \(installed.ruleCount) 条规则。"
                    }
                    importMessageIsError = false
                    importPlan = nil
                    Task { await store.reload() }
                } catch {
                    importMessage = error.localizedDescription
                    importMessageIsError = true
                    importPlan = nil
                }
            }
        }
    }
}

private struct RuleImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: PurposeRuleImportPlan
    let install: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("导入预览").font(.title2.bold())
                Text(plan.candidateURL.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                changeCount("新增", plan.added.count, .green)
                changeCount("更新", plan.updated.count, .blue)
                changeCount("未变化", plan.unchanged.count, .secondary)
                changeCount("安装后总数", plan.mergedRules.count, .primary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ruleChanges("新增规则", rules: plan.added, tint: .green)
                    ruleChanges("更新规则", rules: plan.updated, tint: .blue)
                    ruleChanges("未变化", rules: plan.unchanged, tint: .secondary)
                    if !plan.issues.isEmpty {
                        Divider()
                        Text("校验信息").font(.headline)
                        ForEach(Array(plan.issues.enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: issue.severity == .error ? "xmark.circle" : "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Text("安装只会更新 LaunchScope 的本地识别规则，不会启动、停止、启用或禁用后台任务。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("安装规则", action: install)
                    .buttonStyle(.borderedProminent)
                    .disabled(!plan.canInstall)
            }
        }
        .padding(24)
        .frame(width: 680, height: 560)
    }

    private func changeCount(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)").font(.title2.bold()).monospacedDigit().foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func ruleChanges(_ title: String, rules: [PurposeRule], tint: Color) -> some View {
        if !rules.isEmpty {
            Text(title).font(.headline).foregroundStyle(tint)
            ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name).fontWeight(.semibold)
                    Text(rule.id ?? "缺少规则 ID")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(rule.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("隐私与安全边界").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            privacyRow("不联网", "扫描、识别和管理全部在本机完成。", "network.slash")
            privacyRow("应用内不运行 AI", "可复制经过脱敏的识别上下文；用途仍来自本地规则与可验证路径推断。", "brain.head.profile")
            privacyRow("不采集遥测", "没有分析 SDK、崩溃上传或用户账户。", "waveform.path.ecg.rectangle")
            privacyRow("不删除数据", "启停和禁用只改变 launchd 状态，不删除应用、plist 或用户文件。", "trash.slash")
            privacyRow("系统项需授权", "管理 LaunchDaemon 时使用 macOS 标准管理员授权窗口。", "lock.shield")
            Spacer()
        }
        .padding(24)
        .frame(width: 590, height: 430)
    }

    private func privacyRow(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
