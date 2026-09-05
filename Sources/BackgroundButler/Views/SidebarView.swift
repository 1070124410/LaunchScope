import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List(selection: $store.filter) {
            Section {
                filterRow(.overview)
                filterRow(.aiIntegration)
            }

            Section("状态") {
                filterRow(.all)
                filterRow(.running)
                filterRow(.disabled)
                filterRow(.scheduled)
                filterRow(.attention)
            }

            Section("识别与范围") {
                filterRow(.unknown)
                filterRow(.system)
            }
        }
        .navigationTitle("LaunchScope")
        .safeAreaInset(edge: .top) { brandHeader }
        .safeAreaInset(edge: .bottom) { privacyFooter }
        .onChange(of: store.filter) { _, newValue in store.selectFilter(newValue) }
    }

    private var brandHeader: some View {
        HStack(spacing: 11) {
            Image(systemName: "switch.2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("LaunchScope").font(.headline)
                Text("macOS 后台管家")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Apple 核心服务默认隐藏", systemImage: "checkmark.shield")
                .font(.caption.weight(.medium))
            if let date = store.lastUpdated {
                Text("更新于 \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.bar)
    }

    private func filterRow(_ filter: SidebarFilter) -> some View {
        HStack {
            Label(filter.title, systemImage: filter.icon)
            Spacer()
            if filter != .aiIntegration {
                Text("\(store.count(for: filter))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(filter == .attention && store.count(for: filter) > 0 ? .orange : .secondary)
            }
        }
        .tag(filter)
    }
}
