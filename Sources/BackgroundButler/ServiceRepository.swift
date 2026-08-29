import Foundation

protocol BackgroundServiceRepository: Sendable {
    func snapshot() async -> ServiceSnapshot
    func perform(_ action: ManagementAction, on item: LaunchItem) async throws
}

struct SystemBackgroundServiceRepository: BackgroundServiceRepository {
    func snapshot() async -> ServiceSnapshot {
        let items = await Task.detached(priority: .userInitiated) {
            LaunchdScanner().scan()
        }.value
        return ServiceSnapshot(items: items, generatedAt: Date())
    }

    func perform(_ action: ManagementAction, on item: LaunchItem) async throws {
        try await Task.detached(priority: .userInitiated) {
            try LaunchdManager().perform(action, on: item)
        }.value
    }
}
