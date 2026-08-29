import Foundation

struct PurposeRule: Codable, Hashable, Sendable {
    let match: [String]
    let name: String
    let summary: String
    let vendor: String
    let category: String

    var info: PurposeInfo {
        PurposeInfo(name: name, summary: summary, vendor: vendor, category: category, confidence: .exact)
    }
}

struct PurposeCatalog: Sendable {
    private let customRules: [PurposeRule]

    init(customRules: [PurposeRule] = PurposeRuleStore.load()) {
        self.customRules = customRules
    }

    private struct Rule: Sendable {
        let needles: [String]
        let info: PurposeInfo
    }

    private static let rules: [Rule] = [
        rule(["io.telepresence.rootd"], "Telepresence 特权代理", "为 Telepresence 提供需要管理员权限的网络能力。若不做 Kubernetes 集群联调，通常不需要常驻。", "Telepresence", "开发工具"),
        rule(["io.telepresence.daemon"], "Telepresence 集群代理", "连接本机与 Kubernetes 集群的开发代理。若不做集群联调，通常不需要常驻。", "Telepresence", "开发工具"),
        rule(["tokei.app"], "Tokei 时间工具", "登录后自动打开 Tokei 应用。", "Tokei", "桌面工具"),
        rule(["gitlab-runner"], "GitLab Runner", "在本机领取并执行 GitLab CI 任务；会运行仓库提供的构建脚本。", "GitLab", "开发工具"),
        rule(["mysql"], "MySQL 数据库", "本机 MySQL 数据库服务，供开发项目连接。", "Oracle / Homebrew", "数据库"),
        rule(["redis"], "Redis 数据库", "本机 Redis 缓存与键值数据库服务。", "Redis / Homebrew", "数据库"),
        rule(["googleupdater"], "Google 软件更新器", "定时检查 Chrome 等 Google 应用更新。", "Google", "软件更新"),
        rule(["docker.vmnetd"], "Docker 虚拟机网络服务", "为 Docker Desktop 虚拟机配置网络。Docker 容器运行时需要。", "Docker", "容器工具"),
        rule(["docker.socket"], "Docker 特权套接字", "为 Docker Desktop 提供需要管理员权限的套接字能力。", "Docker", "容器工具"),
        rule(["com.docker.helper"], "Docker 应用辅助项", "由 Docker Desktop 注册的当前用户辅助任务。", "Docker", "容器工具"),
        rule(["cleanmymac5.healthmonitor"], "CleanMyMac 健康监控", "监控磁盘空间、内存等系统状态并提供提醒。", "MacPaw", "系统工具"),
        rule(["cleanmymac5.menu"], "CleanMyMac 菜单栏", "在菜单栏展示 CleanMyMac 状态和快捷功能。", "MacPaw", "系统工具"),
        rule(["cleanmymac5.agent"], "CleanMyMac 特权代理", "执行需要管理员权限的清理和维护操作。", "MacPaw", "系统工具"),
        rule(["uuremote.daemon"], "UU 远程系统服务", "为网易 UU 远程提供整机级连接和远程控制能力。", "网易", "远程控制"),
        rule(["uuremote.agent"], "UU 远程用户代理", "为当前用户启动 UU 远程设备发现和连接服务。", "网易", "远程控制"),
        rule(["sogou"], "搜狗输入法服务", "为搜狗输入法提供候选、更新或任务管理能力。", "搜狗", "输入法"),
        rule(["netdisk_service", "baidunetdisk"], "百度网盘后台服务", "让百度网盘在主窗口关闭后继续处理同步和传输。", "百度", "云盘"),
        rule(["postman"], "Postman 后台组件", "支持 Postman 更新、API 调试和本机代理能力。", "Postman", "开发工具"),
        rule(["cn.better365.ishotprohelper"], "iShot Pro 截图辅助项", "为 iShot Pro 提供截图、录屏或快捷键相关的后台能力。", "Better365", "截图工具")
    ]

    private static func rule(_ needles: [String], _ name: String, _ summary: String, _ vendor: String, _ category: String) -> Rule {
        Rule(needles: needles, info: PurposeInfo(name: name, summary: summary, vendor: vendor, category: category, confidence: .exact))
    }

    func resolve(label: String, program: String, arguments: [String]) -> PurposeInfo {
        let haystack = ([label, program] + arguments).joined(separator: " ").lowercased()
        if let custom = customRules.first(where: { rule in rule.match.contains(where: { haystack.contains($0.lowercased()) }) }) {
            return custom.info
        }
        if let match = Self.rules.first(where: { rule in rule.needles.contains(where: haystack.contains) }) {
            return match.info
        }

        let inferred: (String, String)? = {
            if haystack.contains("/applications/") {
                let component = program.components(separatedBy: "/Applications/").last?.components(separatedBy: ".app/").first
                if let component, !component.isEmpty { return (component, "应用附带的后台组件") }
            }
            if haystack.contains("homebrew") || haystack.contains("/opt/homebrew/") { return ("Homebrew 服务", "由 Homebrew 安装的本地服务") }
            return nil
        }()

        if let inferred {
            return PurposeInfo(
                name: inferred.0,
                summary: "\(inferred.1)。具体用途需要结合命令路径和安装该应用时的功能确认。",
                vendor: "未确认",
                category: "其他",
                confidence: .inferred
            )
        }

        return PurposeInfo(
            name: label,
            summary: "暂时无法从已知规则确认用途。可查看下方可执行文件、参数和配置来源后再决定是否禁用。",
            vendor: "未知",
            category: "未分类",
            confidence: .unknown
        )
    }

    static func lookup(label: String, program: String, arguments: [String]) -> PurposeInfo {
        PurposeCatalog(customRules: []).resolve(label: label, program: program, arguments: arguments)
    }
}
