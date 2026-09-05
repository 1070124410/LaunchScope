import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedChangeID: SnapshotChange.ID?
    @State private var hasAppeared = false

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 14)]

    var body: some View {
        ZStack {
            DashboardBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    metrics
                    recentChangesSection
                    Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                        GridRow {
                            recognitionSection
                            attentionSection
                        }
                        GridRow {
                            categorySection
                            workflowSection
                        }
                    }
                }
                .padding(24)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared || reduceMotion ? 0 : 12)
            }
        }
        .navigationTitle("本机总览")
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1), value: store.snapshotHistory.changes)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 1)) {
                hasAppeared = true
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.46, blue: 0.98),
                            Color(red: 0.31, green: 0.25, blue: 0.91),
                            Color(red: 0.47, green: 0.18, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 310, height: 310)
                .offset(x: 82, y: -92)
            Circle()
                .fill(.cyan.opacity(0.20))
                .frame(width: 190, height: 190)
                .blur(radius: 22)
                .offset(x: -75, y: 112)

            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 13) {
                    Label("本机后台控制中心", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.13), in: Capsule())

                    Text("看懂每一个\n后台项")
                        .font(.system(size: 39, weight: .bold, design: .rounded))
                        .tracking(-1.1)
                        .foregroundStyle(.white)
                        .lineSpacing(-2)

                    Text("先解释来源和影响，再由你决定是否管理。\n扫描不联网，也不会删除应用或数据。")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            store.selectFilter(.all)
                        } label: {
                            Label("查看全部", systemImage: "arrow.right")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.indigo)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 9)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(PressableCardButtonStyle())

                        Button {
                            store.selectFilter(.attention)
                        } label: {
                            Label("\(store.statistics.attention) 项需关注", systemImage: "exclamationmark.triangle.fill")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 9)
                                .background(.white.opacity(0.14), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.24)))
                        }
                        .buttonStyle(PressableCardButtonStyle())
                    }
                }
                Spacer(minLength: 10)
                SnapshotOrb(
                    total: store.statistics.total,
                    recognizedPercent: store.statistics.recognizedPercent
                )
                .padding(.trailing, 28)
            }
            .padding(28)
        }
        .frame(minHeight: 270)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.16))
        )
        .shadow(color: .indigo.opacity(0.24), radius: 28, y: 15)
        .accessibilityElement(children: .contain)
    }

    private var metrics: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            MetricCard(
                title: "全部后台项",
                value: "\(store.statistics.total)",
                detail: "第三方持久化任务",
                icon: "square.stack.3d.up.fill",
                tint: .blue,
                progress: 1
            ) {
                store.selectFilter(.all)
            }
            MetricCard(
                title: "正在运行",
                value: "\(store.statistics.running)",
                detail: memoryDetail,
                icon: "play.fill",
                tint: .green,
                progress: ratio(store.statistics.running)
            ) {
                store.selectFilter(.running)
            }
            MetricCard(
                title: "最近变化",
                value: "\(store.snapshotHistory.changes.count)",
                detail: "本机保留最近 30 天",
                icon: "clock.arrow.circlepath",
                tint: .indigo,
                progress: min(Double(store.snapshotHistory.changes.count) / 10, 1)
            )
            MetricCard(
                title: "用途未知",
                value: "\(store.statistics.unknown)",
                detail: "建议优先核对证据",
                icon: "questionmark.diamond.fill",
                tint: .orange,
                progress: ratio(store.statistics.unknown)
            ) {
                store.selectFilter(.unknown)
            }
        }
    }

    private var recentChangesSection: some View {
        SurfaceCard(title: "最近变化", icon: "clock.arrow.circlepath") {
            if let historyError = store.historyError {
                Label(historyError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.vertical, 10)
            } else if store.snapshotHistory.changes.isEmpty {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(.green.opacity(0.12))
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.snapshotHistory.didEstablishBaseline ? "变化基线已建立" : "本机状态保持稳定")
                            .font(.title3.weight(.semibold))
                        Text(store.snapshotHistory.didEstablishBaseline
                             ? "下次刷新将开始记录新增、移除、配置与状态变化。"
                             : baselineDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.reload() }
                    } label: {
                        Label(store.isLoading ? "检查中" : "再次检查", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(store.isLoading)
                }
                .padding(.vertical, 7)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.snapshotHistory.changes.prefix(6).enumerated()), id: \.element.id) { index, change in
                        changeRow(change)
                        if index < min(store.snapshotHistory.changes.count, 6) - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func changeRow(_ change: SnapshotChange) -> some View {
        let isExpanded = expandedChangeID == change.id
        let isPresent = store.items.contains { $0.id == change.itemID }

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1)) {
                    expandedChangeID = isExpanded ? nil : change.id
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: change.kind.icon)
                        .font(.title3)
                        .foregroundStyle(changeTint(change))
                        .frame(width: 34, height: 34)
                        .background(changeTint(change).opacity(0.11), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(change.itemName).fontWeight(.semibold)
                            Text(change.kind.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(changeTint(change))
                        }
                        Text(change.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(change.occurredAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded && !reduceMotion ? 180 : 0))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(change.itemName)，\(change.kind.title)，\(change.summary)")
            .accessibilityHint(isExpanded ? "收起变化详情" : "展开变化详情")

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(change.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if isPresent {
                        Button("查看当前后台项", systemImage: "arrow.right.circle") {
                            store.open(change)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Label("该项目当前不在扫描结果中", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 46)
                .padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var recognitionSection: some View {
        SurfaceCard(title: "识别覆盖", icon: "checkmark.seal.fill") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(store.statistics.recognizedPercent)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .padding(10)
                        .background(.blue.opacity(0.10), in: Circle())
                }

                ProgressView(value: Double(store.statistics.recognizedPercent), total: 100)
                    .tint(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("规则优先，路径推断次之；证据不足的项目会明确标为未知。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var attentionSection: some View {
        SurfaceCard(title: "优先查看", icon: "exclamationmark.triangle.fill") {
            if store.highlightedItems.isEmpty {
                Label("当前没有运行异常或正在运行的未知项目", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.highlightedItems.prefix(3).enumerated()), id: \.element.id) { index, item in
                        Button {
                            store.filter = .all
                            store.selection = item.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.attentionLevel.icon)
                                    .foregroundStyle(item.attentionLevel >= .warning ? .orange : .secondary)
                                    .frame(width: 30, height: 30)
                                    .background(.orange.opacity(0.10), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.purpose.name).fontWeight(.medium).lineLimit(1)
                                    Text(item.attentionReason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if index < min(store.highlightedItems.count, 3) - 1 { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var categorySection: some View {
        SurfaceCard(title: "类别分布", icon: "chart.bar.fill") {
            let maximum = max(store.categoryCounts.first?.count ?? 1, 1)
            VStack(spacing: 12) {
                ForEach(store.categoryCounts.prefix(6), id: \.name) { category in
                    HStack(spacing: 10) {
                        Text(category.name)
                            .font(.callout.weight(.medium))
                            .frame(width: 76, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .indigo],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: max(9, proxy.size.width * CGFloat(category.count) / CGFloat(maximum)),
                                    height: 8
                                )
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 16)
                        Text("\(category.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workflowSection: some View {
        SurfaceCard(title: "安全工作流", icon: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 0) {
                WorkflowStep(number: "1", title: "扫描", detail: "只读获取配置与真实运行状态", tint: .blue, showsLine: true)
                WorkflowStep(number: "2", title: "解释", detail: "区分规则、推断和未知证据", tint: .indigo, showsLine: true)
                WorkflowStep(number: "3", title: "确认", detail: "由你决定是否执行管理操作", tint: .purple, showsLine: true)
                WorkflowStep(number: "4", title: "复查", detail: "重新读取系统状态确认结果", tint: .green, showsLine: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var memoryDetail: String {
        store.statistics.residentMemoryMB > 0
            ? String(format: "已知 RSS %.0f MB", store.statistics.residentMemoryMB)
            : "正在读取资源占用"
    }

    private var baselineDescription: String {
        guard let date = store.snapshotHistory.baselineDate else { return "完成首次刷新后开始记录。" }
        return "自 \(date.formatted(date: .abbreviated, time: .shortened)) 起，没有检测到新的后台变化。"
    }

    private func ratio(_ value: Int) -> Double {
        guard store.statistics.total > 0 else { return 0 }
        return Double(value) / Double(store.statistics.total)
    }

    private func changeTint(_ change: SnapshotChange) -> Color {
        switch change.attentionLevel {
        case .normal: .secondary
        case .notice: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

private struct DashboardBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [.blue.opacity(0.08), .clear, .purple.opacity(0.06)]
                    : [.blue.opacity(0.055), .clear, .indigo.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct SnapshotOrb: View {
    let total: Int
    let recognizedPercent: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 15)
            Circle()
                .trim(from: 0, to: CGFloat(recognizedPercent) / 100)
                .stroke(
                    LinearGradient(
                        colors: [.white, .cyan.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(total)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("后台项")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .foregroundStyle(.white)
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("共 \(total) 个后台项，识别覆盖 \(recognizedPercent)%")
    }
}

private struct MetricCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    let progress: Double
    var action: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityLabel("\(title)，\(value)，\(detail)")
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                Text(value)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(5, proxy.size.width * max(0, min(progress, 1))))
                    }
            }
            .frame(height: 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                : AnyShapeStyle(.ultraThinMaterial),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isHovering
                        ? tint.opacity(0.30)
                        : Color(nsColor: .separatorColor).opacity(0.28)
                )
        )
        .shadow(color: .black.opacity(isHovering ? 0.10 : 0.035), radius: isHovering ? 18 : 9, y: isHovering ? 8 : 4)
        .offset(y: isHovering && !reduceMotion ? -3 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct WorkflowStep: View {
    let number: String
    let title: String
    let detail: String
    let tint: Color
    let showsLine: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(number)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .background(tint, in: Circle())
                if showsLine {
                    Rectangle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 2, height: 28)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 3)
            Spacer()
        }
    }
}
