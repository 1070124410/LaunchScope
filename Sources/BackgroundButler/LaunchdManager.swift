import Foundation

enum ManagementAction: String, Sendable {
    case enable
    case disable
    case start
    case stop

    var title: String {
        switch self {
        case .enable: "启用"
        case .disable: "禁用"
        case .start: "启动"
        case .stop: "临时停止"
        }
    }
}

enum ManagementError: LocalizedError {
    case invalidLabel
    case cancelled
    case unavailable(String)
    case commandFailed(String)
    case operationDidNotTakeEffect(String)

    var errorDescription: String? {
        switch self {
        case .invalidLabel: "启动项名称包含不安全字符，已拒绝操作。"
        case .cancelled: "操作已取消。"
        case .unavailable(let message): message
        case .commandFailed(let message): message.isEmpty ? "操作失败，请查看启动项详情。" : message
        case .operationDidNotTakeEffect(let message): message
        }
    }
}

struct LaunchdManager: Sendable {
    private let uid = getuid()
    private let launchctlRunner: @Sendable ([String]) -> CommandResult
    private let privilegedRunner: @Sendable ([String]) -> CommandResult
    private let verificationAttempts: Int

    init(launchctlRunner: @escaping @Sendable ([String]) -> CommandResult = {
        CommandRunner.run("/bin/launchctl", $0)
    }, privilegedRunner: @escaping @Sendable ([String]) -> CommandResult = {
        CommandRunner.run("/usr/bin/osascript", $0)
    }, verificationAttempts: Int = 5) {
        self.launchctlRunner = launchctlRunner
        self.privilegedRunner = privilegedRunner
        self.verificationAttempts = max(1, verificationAttempts)
    }

    func perform(_ action: ManagementAction, on item: LaunchItem) throws {
        guard ShellSafety.validLabel(item.label) else { throw ManagementError.invalidLabel }
        if item.domain == .system {
            try performPrivileged(action, on: item)
        } else {
            try performUser(action, on: item)
        }
    }

    private func performUser(_ action: ManagementAction, on item: LaunchItem) throws {
        let target = "gui/\(uid)/\(item.label)"
        let commands: [[String]]
        switch action {
        case .disable:
            commands = [["disable", target], ["bootout", target]]
        case .stop:
            commands = [["bootout", target]]
        case .enable:
            if let path = item.plistPath {
                commands = [["enable", target], ["bootstrap", "gui/\(uid)", path]]
            } else {
                // 动态任务没有 plist；enable 只解除 launchctl 的禁用标记，
                // 原应用下次提交任务时才会真正启动。
                commands = [["enable", target]]
            }
        case .start:
            if let path = item.plistPath {
                commands = [["bootstrap", "gui/\(uid)", path], ["kickstart", "-k", target]]
            } else {
                commands = [["kickstart", "-k", target]]
            }
        }
        try runLaunchctlCommands(commands, tolerateMissingOnBootout: true)
        if action == .stop || action == .disable {
            try verifyUnloaded(target: target, itemName: item.purpose.name)
        }
    }

    private func performPrivileged(_ action: ManagementAction, on item: LaunchItem) throws {
        let target = "system/\(item.label)"
        let launchctl = "/bin/launchctl"
        var fragments: [String]
        switch action {
        case .disable:
            fragments = [
                "\(launchctl) disable \(ShellSafety.quoted(target))",
                "\(launchctl) bootout \(ShellSafety.quoted(target)) 2>/dev/null || { \(launchctl) print \(ShellSafety.quoted(target)) >/dev/null 2>&1 && exit 1 || true; }"
            ]
        case .stop:
            fragments = ["\(launchctl) bootout \(ShellSafety.quoted(target))"]
        case .enable:
            if let path = item.plistPath {
                fragments = ["\(launchctl) enable \(ShellSafety.quoted(target))", "\(launchctl) bootstrap system \(ShellSafety.quoted(path)) || true"]
            } else {
                fragments = ["\(launchctl) enable \(ShellSafety.quoted(target))"]
            }
        case .start:
            if let path = item.plistPath {
                fragments = ["\(launchctl) bootstrap system \(ShellSafety.quoted(path)) || true", "\(launchctl) kickstart -k \(ShellSafety.quoted(target))"]
            } else {
                fragments = ["\(launchctl) kickstart -k \(ShellSafety.quoted(target))"]
            }
        }

        let shellCommand = fragments.joined(separator: "; ")
        let script = "do shell script \(appleScriptString(shellCommand)) with administrator privileges"
        let result = privilegedRunner(["-e", script])
        if result.exitCode != 0 {
            let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            if isAuthorizationCancellation(message) { throw ManagementError.cancelled }
            throw ManagementError.commandFailed(message)
        }
        if action == .stop || action == .disable {
            try verifyUnloaded(target: target, itemName: item.purpose.name)
        }
    }

    private func runLaunchctlCommands(_ commands: [[String]], tolerateMissingOnBootout: Bool) throws {
        for command in commands {
            let result = launchctlRunner(command)
            if result.exitCode != 0 {
                let isMissingBootout = tolerateMissingOnBootout && command.first == "bootout" && result.error.contains("No such process")
                if !isMissingBootout { throw ManagementError.commandFailed(result.error.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
        }
    }

    private func verifyUnloaded(target: String, itemName: String) throws {
        for attempt in 0..<verificationAttempts {
            let result = launchctlRunner(["print", target])
            if result.exitCode != 0 { return }
            if attempt + 1 < verificationAttempts {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        throw ManagementError.operationDidNotTakeEffect(
            "停止命令已经执行，但“\(itemName)”仍在运行。它可能被主应用重新创建；请改用“禁用”，或先退出对应的主应用。"
        )
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func isAuthorizationCancellation(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("(-128)")
            || normalized.contains("user canceled")
            || normalized.contains("user cancelled")
            || normalized.contains("用户已取消")
    }
}
