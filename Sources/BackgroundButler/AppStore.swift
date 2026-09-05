import Combine
import Foundation

struct PendingOperation: Sendable {
    let action: ManagementAction
    let item: LaunchItem
}

@MainActor
final class AppStore: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var selection: LaunchItem.ID?
    @Published var filter: SidebarFilter = .overview
    @Published var sort: ServiceSort = .status
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var operationMessage: String?
    @Published var pendingAction: ManagementAction?
    @Published var pendingItem: LaunchItem?
    @Published var lastUpdated: Date?
    @Published var snapshotHistory: SnapshotHistory = .empty
    @Published var historyError: String?
    private let repository: any BackgroundServiceRepository
    private let historyStore: SnapshotHistoryStore?

    init(
        repository: any BackgroundServiceRepository = SystemBackgroundServiceRepository(),
        historyStore: SnapshotHistoryStore? = nil
    ) {
        self.repository = repository
        self.historyStore = historyStore
    }

    var filteredItems: [LaunchItem] {
        let filtered = items.filter { item in
            let matchesFilter: Bool = switch filter {
            case .overview: true
            case .aiIntegration: true
            case .all: true
            case .running: item.status == .running
            case .disabled: item.status == .disabled
            case .scheduled: item.schedule != nil
            case .attention: item.needsAttention || (item.purpose.confidence == .unknown && item.status == .running)
            case .unknown: item.purpose.confidence == .unknown
            case .system: item.domain == .system
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            let text = [item.purpose.name, item.purpose.summary, item.label, item.program, item.purpose.vendor, item.purpose.category].joined(separator: " ")
            return text.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted(by: sortPredicate)
    }

    var selectedItem: LaunchItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    func count(for filter: SidebarFilter) -> Int {
        switch filter {
        case .overview: items.count
        case .aiIntegration: 0
        case .all: items.count
        case .running: items.count { $0.status == .running }
        case .disabled: items.count { $0.status == .disabled }
        case .scheduled: items.count { $0.schedule != nil }
        case .attention: items.count { $0.needsAttention || ($0.purpose.confidence == .unknown && $0.status == .running) }
        case .unknown: items.count { $0.purpose.confidence == .unknown }
        case .system: items.count { $0.domain == .system }
        }
    }

    var snapshot: ServiceSnapshot { ServiceSnapshot(items: items, generatedAt: lastUpdated ?? Date()) }
    var statistics: ServiceStatistics { snapshot.statistics }

    var categoryCounts: [(name: String, count: Int)] {
        Dictionary(grouping: items, by: { $0.purpose.category })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var highlightedItems: [LaunchItem] {
        items.filter { $0.attentionLevel >= .warning }
            .sorted { $0.attentionLevel > $1.attentionLevel }
            .prefix(5)
            .map { $0 }
    }

    var reportMarkdown: String { ReportExporter.markdown(snapshot: snapshot) }

    func reload() async {
        isLoading = true
        let result = await repository.snapshot()
        items = result.items
        lastUpdated = result.generatedAt
        if let historyStore {
            do {
                snapshotHistory = try await historyStore.record(result)
                historyError = nil
            } catch {
                historyError = "变化历史暂时无法保存：\(error.localizedDescription)"
            }
        }
        if selection == nil || !items.contains(where: { $0.id == selection }) {
            selection = filter == .overview || filter == .aiIntegration ? nil : (filteredItems.first?.id ?? items.first?.id)
        }
        isLoading = false
    }

    func request(_ action: ManagementAction, item: LaunchItem) {
        pendingAction = action
        pendingItem = item
    }

    func takePendingOperation() -> PendingOperation? {
        guard let action = pendingAction, let item = pendingItem else { return nil }
        pendingAction = nil
        pendingItem = nil
        return PendingOperation(action: action, item: item)
    }

    func perform(_ operation: PendingOperation) async {
        isLoading = true
        do {
            try await repository.perform(operation.action, on: operation.item)
            operationMessage = "已\(operation.action.title)：\(operation.item.purpose.name)"
        } catch ManagementError.cancelled {
            operationMessage = nil
        } catch {
            operationMessage = error.localizedDescription
        }
        await reload()
    }

    func selectFilter(_ newFilter: SidebarFilter) {
        filter = newFilter
        if newFilter == .overview || newFilter == .aiIntegration {
            selection = nil
        } else if selection == nil || !filteredItems.contains(where: { $0.id == selection }) {
            selection = filteredItems.first?.id
        }
    }

    func open(_ change: SnapshotChange) {
        guard items.contains(where: { $0.id == change.itemID }) else { return }
        filter = .all
        selection = change.itemID
    }

    private func sortPredicate(_ lhs: LaunchItem, _ rhs: LaunchItem) -> Bool {
        switch sort {
        case .name:
            return lhs.purpose.name.localizedStandardCompare(rhs.purpose.name) == .orderedAscending
        case .cpu:
            return (lhs.usage?.cpuPercent ?? -1) > (rhs.usage?.cpuPercent ?? -1)
        case .status:
            if lhs.attentionLevel != rhs.attentionLevel { return lhs.attentionLevel > rhs.attentionLevel }
            if lhs.status != rhs.status { return statusOrder(lhs.status) < statusOrder(rhs.status) }
            return lhs.purpose.name.localizedStandardCompare(rhs.purpose.name) == .orderedAscending
        }
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
}
