import XCTest
@testable import BackgroundButler

private actor TestRepository: BackgroundServiceRepository {
    private(set) var count = 0
    let items: [LaunchItem]

    init(items: [LaunchItem] = []) {
        self.items = items
    }

    func snapshot() async -> ServiceSnapshot {
        ServiceSnapshot(items: items, generatedAt: Date(timeIntervalSince1970: 0))
    }

    func perform(_ action: ManagementAction, on item: LaunchItem) async throws {
        count += 1
    }
}

private actor CancellingRepository: BackgroundServiceRepository {
    func snapshot() async -> ServiceSnapshot {
        ServiceSnapshot(items: [], generatedAt: Date(timeIntervalSince1970: 0))
    }

    func perform(_ action: ManagementAction, on item: LaunchItem) async throws {
        throw ManagementError.cancelled
    }
}

final class AppStoreTests: XCTestCase {
    @MainActor
    func testDialogDismissalDoesNotDiscardConfirmedOperation() async {
        let repository = TestRepository()
        let store = AppStore(repository: repository)
        store.request(.disable, item: fixtureItem())

        let operation = store.takePendingOperation()
        // SwiftUI confirmationDialog dismisses and drives isPresented=false
        // before the Task created by the button handler gets scheduled.
        store.pendingAction = nil
        store.pendingItem = nil
        await store.perform(try! XCTUnwrap(operation))

        let count = await repository.count
        XCTAssertEqual(count, 1, "The confirmed operation must survive dialog dismissal.")
    }

    @MainActor
    func testAdministratorAuthorizationCancellationDoesNotShowErrorAlert() async {
        let store = AppStore(repository: CancellingRepository())

        await store.perform(PendingOperation(action: .disable, item: fixtureItem()))

        XCTAssertNil(store.operationMessage)
    }

    private func fixtureItem() -> LaunchItem {
        LaunchItem(
            label: "local.backgroundbutler.ui-fixture",
            domain: .user,
            plistPath: "/tmp/local.backgroundbutler.ui-fixture.plist",
            program: "/bin/true",
            arguments: ["/bin/true"],
            runAtLoad: true,
            keepAlive: false,
            schedule: nil,
            status: .running,
            pid: 123,
            lastExitCode: nil,
            usage: nil,
            purpose: PurposeInfo(
                name: "界面竞态测试",
                summary: "确认操作不能被弹窗关闭清空",
                vendor: "BackgroundButler",
                category: "测试",
                confidence: .exact
            )
        )
    }
}
