import Foundation

struct CommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
}

enum CommandRunner {
    static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return CommandResult(output: output, error: error, exitCode: process.terminationStatus)
        } catch {
            return CommandResult(output: "", error: error.localizedDescription, exitCode: -1)
        }
    }
}

enum ShellSafety {
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func validLabel(_ label: String) -> Bool {
        !label.isEmpty && label.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }
}
