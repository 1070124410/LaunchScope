import SwiftUI

struct ServiceListView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            List(store.filteredItems, selection: $store.selection) { item in
                ServiceRow(item: item)
                    .tag(item.id)
            }
            .listStyle(.inset)
            .overlay {
                if !store.isLoading && store.filteredItems.isEmpty {
                    ContentUnavailableView.search(text: store.searchText)
                }
            }
        }
        .navigationTitle(store.filter.title)
    }

    private var listHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.filteredItems.count) 项")
                    .font(.headline.monospacedDigit())
                Text("点击查看识别依据与完整启动信息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("排序", selection: $store.sort) {
                ForEach(ServiceSort.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 105)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
    }
}

private struct ServiceRow: View {
    let item: LaunchItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(statusColor.opacity(0.12))
                Image(systemName: item.status.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(item.purpose.name).font(.headline).lineLimit(1)
                    if item.purpose.confidence == .unknown {
                        Image(systemName: "questionmark.diamond.fill").foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(item.status.title).font(.caption.weight(.semibold)).foregroundStyle(statusColor)
                }
                Text(item.label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Label(item.domain.title, systemImage: item.domain.icon)
                    Text("·")
                    Text(item.purpose.category)
                    if let usage = item.usage {
                        Text("·")
                        Text(String(format: "CPU %.1f%%", usage.cpuPercent))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch item.status {
        case .running: .green
        case .scheduled: .blue
        case .failed: .red
        case .disabled, .stopped: .secondary
        }
    }
}
