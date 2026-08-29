import Foundation

struct ParsedPlist: Sendable {
    let label: String
    let program: String
    let arguments: [String]
    let runAtLoad: Bool
    let keepAlive: Bool
    let schedule: String?
}

enum LaunchdParser {
    static func parse(_ url: URL) -> ParsedPlist? {
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = root as? [String: Any],
              let label = dict["Label"] as? String else { return nil }

        let arguments = dict["ProgramArguments"] as? [String] ?? []
        let program = (dict["Program"] as? String) ?? arguments.first ?? ""
        let runAtLoad = dict["RunAtLoad"] as? Bool ?? false
        let keepAlive: Bool = {
            if let bool = dict["KeepAlive"] as? Bool { return bool }
            return dict["KeepAlive"] != nil
        }()
        return ParsedPlist(
            label: label,
            program: program,
            arguments: arguments,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            schedule: scheduleDescription(dict)
        )
    }

    private static func scheduleDescription(_ dict: [String: Any]) -> String? {
        if let interval = dict["StartInterval"] as? Int { return "每 \(interval) 秒" }
        guard let calendar = dict["StartCalendarInterval"] else { return nil }
        let entries: [[String: Any]]
        if let one = calendar as? [String: Any] { entries = [one] }
        else if let many = calendar as? [[String: Any]] { entries = many }
        else { return "按日历计划" }

        return entries.map { entry in
            let weekday = (entry["Weekday"] as? Int).map { "周\($0) " } ?? ""
            let hour = entry["Hour"] as? Int
            let minute = entry["Minute"] as? Int ?? 0
            if let hour { return String(format: "%@%02d:%02d", weekday, hour, minute) }
            return weekday.isEmpty ? "按日历计划" : weekday.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "、")
    }
}

struct LaunchdScanner: Sendable {
    private let uid = getuid()
    private let purposeCatalog: PurposeCatalog

    init(purposeCatalog: PurposeCatalog = PurposeCatalog()) {
        self.purposeCatalog = purposeCatalog
    }

    func scan() -> [LaunchItem] {
        let disabledUser = disabledLabels(domain: .user)
        let disabledSystem = disabledLabels(domain: .system)
        var items: [LaunchItem] = []
        var knownLabels = Set<String>()

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sources: [(String, LaunchDomain)] = [
            ("\(home)/Library/LaunchAgents", .user),
            ("/Library/LaunchAgents", .user),
            ("/Library/LaunchDaemons", .system)
        ]

        for (directory, domain) in sources {
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "plist" {
                guard let parsed = LaunchdParser.parse(url) else { continue }
                knownLabels.insert(parsed.label)
                items.append(makeItem(
                    parsed: parsed,
                    domain: domain,
                    plistPath: url.path,
                    disabled: (domain == .user ? disabledUser : disabledSystem).contains(parsed.label)
                ))
            }
        }

        for label in loadedUserLabels() where !knownLabels.contains(label) && shouldIncludeDynamic(label) {
            let details = runtimeDetails(label: label, domain: .user)
            let parsed = ParsedPlist(
                label: label,
                program: details.program,
                arguments: details.program.isEmpty ? [] : [details.program],
                runAtLoad: false,
                keepAlive: false,
                schedule: nil
            )
            items.append(makeItem(parsed: parsed, domain: .user, plistPath: nil, disabled: disabledUser.contains(label)))
            knownLabels.insert(label)
        }

        // launchctl 会记住没有 plist 的动态任务禁用状态。把它们保留在列表中，
        // 否则用户禁用后反而再也看不到、也无法理解或恢复该任务。
        for label in disabledUser where !knownLabels.contains(label) && shouldIncludeDynamic(label) {
            let parsed = ParsedPlist(label: label, program: "", arguments: [], runAtLoad: false, keepAlive: false, schedule: nil)
            items.append(makeItem(parsed: parsed, domain: .user, plistPath: nil, disabled: true))
            knownLabels.insert(label)
        }

        for label in disabledSystem where !knownLabels.contains(label) && shouldIncludeDynamic(label) {
            let parsed = ParsedPlist(label: label, program: "", arguments: [], runAtLoad: false, keepAlive: false, schedule: nil)
            items.append(makeItem(parsed: parsed, domain: .system, plistPath: nil, disabled: true))
            knownLabels.insert(label)
        }

        return items.sorted {
            if $0.needsAttention != $1.needsAttention { return $0.needsAttention }
            if $0.status != $1.status { return statusOrder($0.status) < statusOrder($1.status) }
            return $0.purpose.name.localizedStandardCompare($1.purpose.name) == .orderedAscending
        }
    }

    private func makeItem(parsed: ParsedPlist, domain: LaunchDomain, plistPath: String?, disabled: Bool) -> LaunchItem {
        let runtime = runtimeDetails(label: parsed.label, domain: domain)
        let lastExit = runtime.lastExitCode
        let status: ItemStatus
        if disabled { status = .disabled }
        else if runtime.pid != nil || runtime.state == "running" { status = .running }
        else if let lastExit, lastExit != 0, runtime.runs > 5 { status = .failed }
        else if parsed.schedule != nil { status = .scheduled }
        else { status = .stopped }

        let program = parsed.program.isEmpty ? runtime.program : parsed.program
        return LaunchItem(
            label: parsed.label,
            domain: domain,
            plistPath: plistPath,
            program: program,
            arguments: parsed.arguments,
            runAtLoad: parsed.runAtLoad,
            keepAlive: parsed.keepAlive,
            schedule: parsed.schedule,
            status: status,
            pid: runtime.pid,
            lastExitCode: lastExit,
            usage: runtime.pid.flatMap(processUsage),
            purpose: purposeCatalog.resolve(label: parsed.label, program: program, arguments: parsed.arguments)
        )
    }

    private func target(_ label: String, domain: LaunchDomain) -> String {
        domain == .user ? "gui/\(uid)/\(label)" : "system/\(label)"
    }

    private func disabledLabels(domain: LaunchDomain) -> Set<String> {
        let scope = domain == .user ? "gui/\(uid)" : "system"
        let output = CommandRunner.run("/bin/launchctl", ["print-disabled", scope]).output
        let pattern = try? NSRegularExpression(pattern: #"\"([^\"]+)\"\s*=>\s*disabled"#)
        let range = NSRange(output.startIndex..., in: output)
        return Set((pattern?.matches(in: output, range: range) ?? []).compactMap { match in
            guard let range = Range(match.range(at: 1), in: output) else { return nil }
            return String(output[range])
        })
    }

    private func loadedUserLabels() -> [String] {
        CommandRunner.run("/bin/launchctl", ["list"]).output
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let columns = line.split(whereSeparator: \ .isWhitespace)
                return columns.count >= 3 ? String(columns[2]) : nil
            }
    }

    private func shouldIncludeDynamic(_ label: String) -> Bool {
        !label.hasPrefix("com.apple.") &&
        !label.hasPrefix("application.") &&
        !label.hasSuffix(".ShipIt") &&
        label != "com.openssh.ssh-agent"
    }

    private func statusOrder(_ status: ItemStatus) -> Int {
        switch status {
        case .failed: 0
        case .running: 1
        case .scheduled: 2
        case .stopped: 3
        case .disabled: 4
        }
    }

    private func runtimeDetails(label: String, domain: LaunchDomain) -> (state: String, pid: Int?, lastExitCode: Int?, runs: Int, program: String) {
        let result = CommandRunner.run("/bin/launchctl", ["print", target(label, domain: domain)])
        guard result.exitCode == 0 else { return ("", nil, nil, 0, "") }
        let output = result.output
        return (
            capture(#"(?m)^\s*state = ([^\n]+)"#, in: output),
            Int(capture(#"(?m)^\s*pid = (\d+)"#, in: output)),
            Int(capture(#"(?m)^\s*last exit code = (\d+)"#, in: output)),
            Int(capture(#"(?m)^\s*runs = (\d+)"#, in: output)) ?? 0,
            capture(#"(?m)^\s*program = ([^\n]+)"#, in: output)
        )
    }

    private func processUsage(pid: Int) -> ProcessUsage? {
        let result = CommandRunner.run("/bin/ps", ["-p", String(pid), "-o", "%cpu=,%mem=,rss="])
        let values = result.output.split(whereSeparator: \ .isWhitespace).compactMap { Double($0) }
        guard values.count >= 3 else { return nil }
        return ProcessUsage(cpuPercent: values[0], memoryPercent: values[1], residentMemoryMB: values[2] / 1024)
    }

    private func capture(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
