import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(title: "全部后台项", value: "\(store.statistics.total)", detail: "第三方持久化任务", icon: "square.stack.3d.up", tint: .blue)
                    MetricCard(title: "正在运行", value: "\(store.statistics.running)", detail: memoryDetail, icon: "play.fill", tint: .green)
                    MetricCard(title: "已禁用", value: "\(store.statistics.disabled)", detail: "不会自动加载", icon: "nosign", tint: .secondary)
                    MetricCard(title: "用途未知", value: "\(store.statistics.unknown)", detail: "建议先核对证据", icon: "questionmark.diamond", tint: .orange)
                }
                recognitionSection
                attentionSection
                categorySection
                workflowSection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("本机总览")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("看懂每一个后台项")
                    .font(.largeTitle.bold())
                Spacer()
                Label("只读扫描", systemImage: "lock.shield")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(.green)
            }
            Text("先解释来源和影响，再由你决定是否管理。扫描不联网，操作不会删除应用或数据。")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var recognitionSection: some View {
        SurfaceCard(title: "识别覆盖", icon: "checkmark.seal") {
            HStack(spacing: 18) {
                Gauge(value: Double(store.statistics.recognizedPercent), in: 0...100) {
                    Text("识别率")
                } currentValueLabel: {
                    Text("\(store.statistics.recognizedPercent)%")
                        .font(.title2.bold())
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.blue)
                .frame(width: 86)
                VStack(alignment: .leading, spacing: 5) {
                    Text("规则优先，推断次之，证据不足就明确标为未知。")
                        .font(.headline)
                    Text("可以通过本地 JSON 规则补充私有工具，不需要修改源码，也不会把进程信息发给 AI。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var attentionSection: some View {
        SurfaceCard(title: "优先查看", icon: "exclamationmark.triangle") {
            if store.highlightedItems.isEmpty {
                Label("当前没有运行异常或正在运行的未知项目", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(store.highlightedItems) { item in
                    Button {
                        store.filter = .all
                        store.selection = item.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.attentionLevel.icon)
                                .foregroundStyle(item.attentionLevel >= .warning ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.purpose.name).fontWeight(.medium)
                                Text(item.attentionReason).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    if item.id != store.highlightedItems.last?.id { Divider() }
                }
            }
        }
    }

    private var categorySection: some View {
        SurfaceCard(title: "类别分布", icon: "chart.bar") {
            let maximum = max(store.categoryCounts.first?.count ?? 1, 1)
            ForEach(store.categoryCounts.prefix(7), id: \.name) { category in
                HStack(spacing: 10) {
                    Text(category.name).frame(width: 84, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.accentColor.opacity(0.72))
                            .frame(width: max(8, proxy.size.width * CGFloat(category.count) / CGFloat(maximum)), height: 7)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 14)
                    Text("\(category.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var workflowSection: some View {
        SurfaceCard(title: "工作方式", icon: "arrow.triangle.branch") {
            HStack(alignment: .top, spacing: 18) {
                WorkflowStep(number: "1", title: "扫描", detail: "读取第三方 launchd 配置与运行状态")
                WorkflowStep(number: "2", title: "解释", detail: "展示规则、推断与原始证据")
                WorkflowStep(number: "3", title: "管理", detail: "确认后执行并复查是否真正生效")
            }
        }
    }

    private var memoryDetail: String {
        store.statistics.residentMemoryMB > 0 ? String(format: "已知 RSS %.0f MB", store.statistics.residentMemoryMB) : "正在读取资源占用"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundStyle(tint)
                Spacer()
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.separator.opacity(0.4)))
    }
}

private struct WorkflowStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
