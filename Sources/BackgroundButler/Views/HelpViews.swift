import AppKit
import SwiftUI

struct RulesHelpView: View {
    @Environment(\.dismiss) private var dismiss

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
        .frame(width: 620, height: 520)
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
            privacyRow("不使用 AI", "用途来自规则与可验证路径推断，未知就明确显示未知。", "brain.head.profile")
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
