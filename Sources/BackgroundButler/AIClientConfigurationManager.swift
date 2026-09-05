import Foundation

enum AIClientKind: String, CaseIterable, Sendable {
    case codex
    case claudeCode
    case cursor
    case claudeDesktop

    var name: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .claudeDesktop: "Claude Desktop"
        }
    }

    var icon: String {
        switch self {
        case .codex: "terminal"
        case .claudeCode: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .claudeDesktop: "bubble.left.and.text.bubble.right"
        }
    }
}

struct AIClientInstallation: Identifiable, Hashable, Sendable {
    enum ApplyMethod: Hashable, Sendable {
        case command(executable: String, arguments: [String], configurationPath: String)
        case json(configurationPath: String)
        case unavailable
    }

    let kind: AIClientKind
    let detected: Bool
    let applyMethod: ApplyMethod

    var id: String { kind.rawValue }
    var name: String { kind.name }

    var configurationPath: String? {
        switch applyMethod {
        case let .command(_, _, path), let .json(path): path
        case .unavailable: nil
        }
    }

    var canApply: Bool {
        detected && configurationPath != nil
    }
}

struct AIClientConfigurationResult: Sendable {
    let clientName: String
    let configurationPath: String
    let backupPath: String?
    let changed: Bool
}

enum AIClientConfigurationError: LocalizedError {
    case invalidConfiguration(String)
    case commandFailed(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): message
        case let .commandFailed(message): message
        case let .unavailable(message): message
        }
    }
}

struct AIClientConfigurationManager: Sendable {
    private let homeDirectory: URL
    private let environmentPath: String

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.homeDirectory = homeDirectory
        self.environmentPath = environmentPath
    }

    func scan(serverPath: String) -> [AIClientInstallation] {
        let codexConfig = homeDirectory.appendingPathComponent(".codex/config.toml").path
        let claudeConfig = homeDirectory.appendingPathComponent(".claude.json").path
        let cursorConfig = homeDirectory.appendingPathComponent(".cursor/mcp.json").path
        let claudeDesktopConfig = homeDirectory
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
            .path

        let codexExecutable = findExecutable("codex")
        let claudeExecutable = findExecutable("claude")
        let cursorDetected = applicationExists("Cursor.app") || directoryExists(".cursor")
        let claudeDesktopDetected = applicationExists("Claude.app") || directoryExists("Library/Application Support/Claude")

        return [
            AIClientInstallation(
                kind: .codex,
                detected: codexExecutable != nil || applicationExists("Codex.app") || directoryExists(".codex"),
                applyMethod: codexExecutable.map {
                    .command(
                        executable: $0,
                        arguments: ["mcp", "add", "launchscope", "--", "/usr/bin/python3", serverPath],
                        configurationPath: codexConfig
                    )
                } ?? .unavailable
            ),
            AIClientInstallation(
                kind: .claudeCode,
                detected: claudeExecutable != nil || directoryExists(".claude"),
                applyMethod: claudeExecutable.map {
                    .command(
                        executable: $0,
                        arguments: ["mcp", "add", "--scope", "user", "launchscope", "--", "/usr/bin/python3", serverPath],
                        configurationPath: claudeConfig
                    )
                } ?? .unavailable
            ),
            AIClientInstallation(
                kind: .cursor,
                detected: cursorDetected,
                applyMethod: cursorDetected ? .json(configurationPath: cursorConfig) : .unavailable
            ),
            AIClientInstallation(
                kind: .claudeDesktop,
                detected: claudeDesktopDetected,
                applyMethod: claudeDesktopDetected ? .json(configurationPath: claudeDesktopConfig) : .unavailable
            ),
        ]
    }

    func apply(_ client: AIClientInstallation, serverPath: String) throws -> AIClientConfigurationResult {
        switch client.applyMethod {
        case let .command(executable, arguments, configurationPath):
            let backup = try backupIfPresent(URL(fileURLWithPath: configurationPath))
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw AIClientConfigurationError.commandFailed(
                    message?.isEmpty == false ? message! : "\(client.name) 注册命令执行失败。"
                )
            }
            return AIClientConfigurationResult(
                clientName: client.name,
                configurationPath: configurationPath,
                backupPath: backup?.path,
                changed: true
            )
        case let .json(configurationPath):
            return try mergeJSONConfiguration(
                clientName: client.name,
                configurationURL: URL(fileURLWithPath: configurationPath),
                serverPath: serverPath
            )
        case .unavailable:
            throw AIClientConfigurationError.unavailable("没有找到可用的 \(client.name) 配置入口。")
        }
    }

    func mergeJSONConfiguration(
        clientName: String,
        configurationURL: URL,
        serverPath: String
    ) throws -> AIClientConfigurationResult {
        let fileManager = FileManager.default
        var root: [String: Any] = [:]
        var permissions: NSNumber = 0o600
        if fileManager.fileExists(atPath: configurationURL.path) {
            let data = try Data(contentsOf: configurationURL)
            let value = try JSONSerialization.jsonObject(with: data)
            guard let object = value as? [String: Any] else {
                throw AIClientConfigurationError.invalidConfiguration("\(configurationURL.path) 顶层必须是 JSON 对象，未执行写入。")
            }
            root = object
            if let attributes = try? fileManager.attributesOfItem(atPath: configurationURL.path),
               let existingPermissions = attributes[.posixPermissions] as? NSNumber {
                permissions = existingPermissions
            }
        }
        var servers: [String: Any]
        if let current = root["mcpServers"] {
            guard let object = current as? [String: Any] else {
                throw AIClientConfigurationError.invalidConfiguration("\(configurationURL.path) 的 mcpServers 必须是 JSON 对象，未执行写入。")
            }
            servers = object
        } else {
            servers = [:]
        }
        let launchscope: [String: Any] = [
            "command": "/usr/bin/python3",
            "args": [serverPath],
        ]
        if let existing = servers["launchscope"] as? NSDictionary,
           existing.isEqual(to: launchscope) {
            return AIClientConfigurationResult(
                clientName: clientName,
                configurationPath: configurationURL.path,
                backupPath: nil,
                changed: false
            )
        }

        servers["launchscope"] = launchscope
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
        try fileManager.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let backup = try backupIfPresent(configurationURL)
        try data.write(to: configurationURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: configurationURL.path)
        return AIClientConfigurationResult(
            clientName: clientName,
            configurationPath: configurationURL.path,
            backupPath: backup?.path,
            changed: true
        )
    }

    private func findExecutable(_ name: String) -> String? {
        let pathDirectories = environmentPath.split(separator: ":").map(String.init)
        let knownDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".local/bin").path,
        ]
        return (pathDirectories + knownDirectories)
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func applicationExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/\(name)") ||
            FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent("Applications/\(name)").path)
    }

    private func directoryExists(_ relativePath: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: homeDirectory.appendingPathComponent(relativePath).path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    private func backupIfPresent(_ url: URL) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let milliseconds = Int(Date().timeIntervalSince1970 * 1_000)
        let backup = url.appendingPathExtension("launchscope-backup-\(milliseconds)")
        try fileManager.copyItem(at: url, to: backup)
        return backup
    }
}
