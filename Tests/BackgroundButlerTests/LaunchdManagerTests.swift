import XCTest
@testable import BackgroundButler

final class LaunchdManagerTests: XCTestCase {
    func testStopDoesNotReportSuccessWhenLaunchctlReturnsIOError() {
        let manager = LaunchdManager(launchctlRunner: { _ in
            CommandResult(
                output: "",
                error: "Boot-out failed: 5: Input/output error\n",
                exitCode: 5
            )
        }, verificationAttempts: 1)

        XCTAssertThrowsError(try manager.perform(.stop, on: runningUserItem()))
    }

    func testStopReportsFailureWhenJobIsStillLoadedAfterSuccessfulBootout() {
        let manager = LaunchdManager(launchctlRunner: { arguments in
            if arguments.first == "bootout" {
                return CommandResult(output: "", error: "", exitCode: 0)
            }
            return CommandResult(output: "state = running\n", error: "", exitCode: 0)
        }, verificationAttempts: 1)

        XCTAssertThrowsError(try manager.perform(.stop, on: runningUserItem())) { error in
            XCTAssertTrue(error.localizedDescription.contains("仍在运行"))
        }
    }

    func testStopSucceedsWhenJobIsAbsent() throws {
        let manager = LaunchdManager(launchctlRunner: { arguments in
            if arguments.first == "bootout" {
                return CommandResult(output: "", error: "Boot-out failed: 3: No such process\n", exitCode: 3)
            }
            return CommandResult(output: "", error: "Bad request.\n", exitCode: 113)
        }, verificationAttempts: 1)

        XCTAssertNoThrow(try manager.perform(.stop, on: runningUserItem()))
    }

    func testCancellingAdministratorAuthorizationIsNotReportedAsCommandFailure() {
        let manager = LaunchdManager(
            launchctlRunner: { _ in CommandResult(output: "", error: "", exitCode: 0) },
            privilegedRunner: { _ in
                CommandResult(output: "", error: "0:108: execution error: 用户已取消。 (-128)\n", exitCode: 1)
            },
            verificationAttempts: 1
        )

        XCTAssertThrowsError(try manager.perform(.stop, on: runningSystemItem())) { error in
            guard case ManagementError.cancelled = error else {
                return XCTFail("Expected cancellation, got \(error)")
            }
        }
    }

    func testRealLaunchdFixtureStopsAndUnloads() throws {
        guard ProcessInfo.processInfo.environment["BACKGROUND_BUTLER_INTEGRATION"] == "1" else {
            throw XCTSkip("Set BACKGROUND_BUTLER_INTEGRATION=1 to exercise real launchctl.")
        }

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/local.backgroundbutler.stop-fixture.plist")
        let scope = "gui/\(getuid())"
        let target = "\(scope)/local.backgroundbutler.stop-fixture"
        _ = CommandRunner.run("/bin/launchctl", ["bootout", target])
        let bootstrap = CommandRunner.run("/bin/launchctl", ["bootstrap", scope, fixtureURL.path])
        XCTAssertEqual(bootstrap.exitCode, 0, bootstrap.error)
        defer { _ = CommandRunner.run("/bin/launchctl", ["bootout", target]) }
        XCTAssertEqual(CommandRunner.run("/bin/launchctl", ["print", target]).exitCode, 0)

        try LaunchdManager().perform(.stop, on: runningUserItem(label: "local.backgroundbutler.stop-fixture"))

        XCTAssertNotEqual(CommandRunner.run("/bin/launchctl", ["print", target]).exitCode, 0)
    }

    private func runningUserItem(label: String = "local.backgroundbutler.fixture") -> LaunchItem {
        LaunchItem(
            label: label,
            domain: .user,
            plistPath: "/tmp/local.backgroundbutler.fixture.plist",
            program: "/bin/sleep",
            arguments: ["/bin/sleep", "600"],
            runAtLoad: true,
            keepAlive: true,
            schedule: nil,
            status: .running,
            pid: 12345,
            lastExitCode: nil,
            usage: nil,
            purpose: PurposeInfo(
                name: "测试任务",
                summary: "停止链路回归测试",
                vendor: "BackgroundButler",
                category: "测试",
                confidence: .exact
            )
        )
    }

    private func runningSystemItem() -> LaunchItem {
        let userItem = runningUserItem(label: "local.backgroundbutler.system-fixture")
        return LaunchItem(
            label: userItem.label,
            domain: .system,
            plistPath: "/Library/LaunchDaemons/local.backgroundbutler.system-fixture.plist",
            program: userItem.program,
            arguments: userItem.arguments,
            runAtLoad: userItem.runAtLoad,
            keepAlive: userItem.keepAlive,
            schedule: userItem.schedule,
            status: userItem.status,
            pid: userItem.pid,
            lastExitCode: userItem.lastExitCode,
            usage: userItem.usage,
            purpose: userItem.purpose
        )
    }
}
