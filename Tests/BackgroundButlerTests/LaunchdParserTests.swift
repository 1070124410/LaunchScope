import Foundation
import XCTest
@testable import BackgroundButler

final class LaunchdParserTests: XCTestCase {
    func testParsesKeepAliveAndInterval() throws {
        let plist: [String: Any] = [
            "Label": "local.test.worker",
            "ProgramArguments": ["/usr/bin/test", "value"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StartInterval": 300
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try XCTUnwrap(LaunchdParser.parse(url))
        XCTAssertEqual(parsed.label, "local.test.worker")
        XCTAssertEqual(parsed.program, "/usr/bin/test")
        XCTAssertTrue(parsed.runAtLoad)
        XCTAssertTrue(parsed.keepAlive)
        XCTAssertEqual(parsed.schedule, "每 300 秒")
    }
}
