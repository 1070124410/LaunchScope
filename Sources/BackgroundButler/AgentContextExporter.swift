import Foundation

enum AgentContextExporter {
    static func recognitionRequest(for item: LaunchItem, homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        let payload: [String: Any] = [
            "protocol": "launchscope.recognition-request",
            "protocolVersion": 1,
            "task": "identify-purpose-rule",
            "service": [
                "label": item.label,
                "domain": item.domain.rawValue,
                "program": sanitized(path: item.program, homeDirectory: homeDirectory),
                "source": sanitized(path: item.plistPath ?? "dynamic-registration", homeDirectory: homeDirectory)
            ],
            "requestedOutput": [
                "protocol": "launchscope.purpose-rules",
                "schemaVersion": 1,
                "preferredSelector": "labels"
            ],
            "privacy": [
                "argumentsOmitted": true,
                "environmentOmitted": true,
                "runtimeIdentifiersOmitted": true
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text + "\n"
    }

    private static func sanitized(path: String, homeDirectory: String) -> String {
        guard !homeDirectory.isEmpty, path.hasPrefix(homeDirectory) else { return path }
        return "$HOME" + path.dropFirst(homeDirectory.count)
    }
}
