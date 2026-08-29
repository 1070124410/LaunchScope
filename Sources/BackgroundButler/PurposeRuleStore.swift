import Foundation

enum PurposeRuleStore {
    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LaunchScope", isDirectory: true)
    }

    static var rulesURL: URL { directoryURL.appendingPathComponent("purpose-rules.json") }

    private static var legacyRulesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BackgroundButler/purpose-rules.json")
    }

    static func load(from url: URL = rulesURL) -> [PurposeRule] {
        let sourceURL = FileManager.default.fileExists(atPath: url.path) ? url : legacyRulesURL
        guard let data = try? Data(contentsOf: sourceURL),
              let rules = try? JSONDecoder().decode([PurposeRule].self, from: data) else { return [] }
        return rules.filter { !$0.match.isEmpty && !$0.name.isEmpty && !$0.summary.isEmpty }
    }

    static let exampleJSON = """
    [
      {
        "match": ["com.example.worker", "/Applications/Example.app"],
        "name": "示例后台服务",
        "summary": "说明它为什么需要在后台运行，以及关闭后的影响。",
        "vendor": "Example",
        "category": "开发工具"
      }
    ]
    """
}
