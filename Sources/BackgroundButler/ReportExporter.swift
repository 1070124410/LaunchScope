import Foundation

enum ReportExporter {
    static func markdown(snapshot: ServiceSnapshot) -> String {
        let stats = snapshot.statistics
        let formatter = ISO8601DateFormatter()
        var lines = [
            "# LaunchScope 本机后台项报告",
            "",
            "生成时间：\(formatter.string(from: snapshot.generatedAt))",
            "",
            "## 摘要",
            "",
            "- 总数：\(stats.total)",
            "- 运行中：\(stats.running)",
            "- 已禁用：\(stats.disabled)",
            "- 定时任务：\(stats.scheduled)",
            "- 用途未知：\(stats.unknown)",
            "- 识别率：\(stats.recognizedPercent)%",
            "",
            "## 后台项",
            "",
            "| 名称 | Label | 状态 | 范围 | 来源 | 用途依据 |",
            "|---|---|---|---|---|---|"
        ]
        for item in snapshot.items {
            lines.append("| \(cell(item.purpose.name)) | `\(cell(item.label))` | \(item.status.title) | \(item.domain.title) | \(item.sourceTitle) | \(item.purpose.confidence.title) |")
        }
        lines += [
            "",
            "## 隐私说明",
            "",
            "本报告不包含命令、参数、环境变量、日志正文、浏览器数据或网络内容。Label 仍可能带有项目特征，公开前请人工检查。"
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func cell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
