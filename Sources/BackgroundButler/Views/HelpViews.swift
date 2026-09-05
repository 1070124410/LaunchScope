import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AIIntegrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedLabel: String?
    @State private var pendingClient: AIClientInstallation?
    @State private var operationMessage: String?
    @State private var isApplying = false

    private let fileManager = FileManager.default
    private let configurationManager = AIClientConfigurationManager()

    private var serverPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/LaunchScopeAI/launchscope_mcp.py")
            .path
    }

    private var codexCommand: String {
        "codex mcp add launchscope -- /usr/bin/python3 \(shellQuoted(serverPath))"
    }

    private var claudeCommand: String {
        "claude mcp add --scope user launchscope -- /usr/bin/python3 \(shellQuoted(serverPath))"
    }

    private var cursorConfiguration: String {
        """
        {
          "mcpServers": {
            "launchscope": {
              "command": "/usr/bin/python3",
              "args": [\(jsonQuoted(serverPath))]
            }
          }
        }
        """
    }

    private var serverAvailable: Bool {
        fileManager.isExecutableFile(atPath: serverPath)
    }

    private var clients: [AIClientInstallation] {
        configurationManager.scan(serverPath: serverPath)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 18) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                        .shadow(color: .blue.opacity(0.18), radius: 14, y: 7)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AI 助手").font(.largeTitle.bold())
                        Text("让支持 MCP 的 AI 看懂后台项，并按 LaunchScope 协议准备可审查的识别规则。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard(title: "本机 MCP", icon: "point.3.connected.trianglepath.dotted") {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: serverAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(serverAvailable ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(serverAvailable ? "已随 LaunchScope 安装" : "当前构建未包含 MCP Server")
                                .fontWeight(.semibold)
                            Text(serverAvailable ? "客户端连接后即可读取隐私快照、校验和预演规则。" : "请使用 release 构建或重新运行构建脚本。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            StatusBadge(text: "7 个工具", icon: "wrench.and.screwdriver", tint: .blue)
                            StatusBadge(text: "本机 stdio", icon: "terminal", tint: .purple)
                            StatusBadge(text: "不联网", icon: "network.slash", tint: .green)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    capabilityCard("读取", "后台项、近期变化、已安装规则", "eye", .blue)
                    capabilityCard("准备", "校验并预演 Rule Pack", "checkmark.seal", .purple)
                    capabilityCard("候选", "经允许保存待审文件", "doc.badge.plus", .orange)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("连接客户端").font(.title2.bold())
                    Text("LaunchScope 只检测本机应用或命令是否存在，不会读取或改写其他客户端的配置。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(clients) { client in
                        connectionRow(
                            client,
                            detail: clientDetail(client.kind),
                            value: configurationValue(client.kind)
                        )
                    }
                }

                SurfaceCard(title: "安全边界", icon: "lock.shield") {
                    Text("MCP 不能安装规则，也不能启动、停止、启用或禁用后台任务。候选规则必须回到 LaunchScope 查看差异并确认安装；后台项管理继续使用 App 内确认和状态回读。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let copiedLabel {
                    Label("已复制 \(copiedLabel) 配置，可粘贴到终端或客户端设置中。", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(32)
            .frame(maxWidth: 1050, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("AI 助手")
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1), value: copiedLabel)
        .confirmationDialog(
            pendingClient.map { "应用到 \($0.name)？" } ?? "应用 MCP 配置？",
            isPresented: Binding(
                get: { pendingClient != nil },
                set: { if !$0 { pendingClient = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let client = pendingClient {
                Button("确认写入配置") { apply(to: client) }
            }
            Button("取消", role: .cancel) { pendingClient = nil }
        } message: {
            if let client = pendingClient {
                Text("只会新增或更新 mcpServers.launchscope，并保留其他设置。目标：\(client.configurationPath ?? "客户端配置")。已有文件会先创建备份。")
            }
        }
        .alert("AI 助手", isPresented: Binding(
            get: { operationMessage != nil },
            set: { if !$0 { operationMessage = nil } }
        )) {
            Button("好") { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "")
        }
    }

    private func capabilityCard(_ title: String, _ detail: String, _ icon: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func connectionRow(_ client: AIClientInstallation, detail: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: client.detected ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(client.detected ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Label(client.name, systemImage: client.kind.icon).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(client.detected ? (client.canApply ? "可自动配置" : "已检测，缺少 CLI") : "未检测到")
                .font(.caption.weight(.medium))
                .foregroundStyle(client.canApply ? Color.green : Color.secondary)
            Button("复制配置", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copiedLabel = client.name
            }
            .buttonStyle(.bordered)
            if client.canApply {
                Button("一键应用", systemImage: "arrow.down.doc") {
                    pendingClient = client
                }
                .buttonStyle(.borderedProminent)
                .disabled(!serverAvailable || isApplying)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func clientDetail(_ kind: AIClientKind) -> String {
        switch kind {
        case .codex: "使用 Codex CLI 注册到用户配置"
        case .claudeCode: "使用 Claude CLI 注册到用户配置"
        case .cursor: "合并到 ~/.cursor/mcp.json"
        case .claudeDesktop: "合并到 Claude Desktop MCP 配置"
        }
    }

    private func configurationValue(_ kind: AIClientKind) -> String {
        switch kind {
        case .codex: codexCommand
        case .claudeCode: claudeCommand
        case .cursor, .claudeDesktop: cursorConfiguration
        }
    }

    private func apply(to client: AIClientInstallation) {
        pendingClient = nil
        isApplying = true
        Task {
            do {
                let path = serverPath
                let result = try await Task.detached {
                    try AIClientConfigurationManager().apply(client, serverPath: path)
                }.value
                if result.changed {
                    operationMessage = if let backup = result.backupPath {
                        "已应用到 \(result.clientName)。原配置备份在：\(backup)"
                    } else {
                        "已应用到 \(result.clientName)：\(result.configurationPath)"
                    }
                } else {
                    operationMessage = "\(result.clientName) 已经使用当前 LaunchScope MCP 配置，无需修改。"
                }
            } catch {
                operationMessage = "配置失败：\(error.localizedDescription)"
            }
            isApplying = false
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func jsonQuoted(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return encoded
    }
}

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
