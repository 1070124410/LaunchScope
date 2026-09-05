import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isExporting = false
    @State private var exportDocument = MarkdownDocument(text: "")
    @State private var presentedSheet: AppSheet?

    var body: some View {
        Group {
            if store.filter == .aiIntegration {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 285)
                } detail: {
                    AIIntegrationView()
                }
            } else if store.filter == .overview {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 285)
                } detail: {
                    DashboardView()
                }
            } else {
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 285)
                } content: {
                ServiceListView()
                    .navigationSplitViewColumnWidth(min: 340, ideal: 410, max: 520)
                } detail: {
                    if let item = store.selectedItem {
                        ServiceDetailView(item: item)
                    } else {
                        ContentUnavailableView(
                            "选择一个后台项",
                            systemImage: "gearshape.2",
                            description: Text("查看用途依据、启动方式、运行证据和管理操作。")
                        )
                    }
                }
            }
        }
        .modifier(BackgroundItemSearchModifier(
            text: $store.searchText,
            enabled: store.filter != .aiIntegration
        ))
        .toolbar { toolbarContent }
        .task { await store.reload() }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { store.pendingAction != nil },
                set: { if !$0 { store.pendingAction = nil; store.pendingItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = store.pendingAction {
                Button("确认\(action.title)", role: action == .disable || action == .stop ? .destructive : nil) {
                    guard let operation = store.takePendingOperation() else { return }
                    Task { await store.perform(operation) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert("LaunchScope", isPresented: Binding(
            get: { store.operationMessage != nil },
            set: { if !$0 { store.operationMessage = nil } }
        )) {
            Button("好") { store.operationMessage = nil }
        } message: {
            Text(store.operationMessage ?? "")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .backgroundButlerMarkdown,
            defaultFilename: "background-services-report"
        ) { _ in }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .rules: RulesHelpView()
            case .privacy: PrivacyView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if store.filter != .aiIntegration {
                Button {
                    Task { await store.reload() }
                } label: {
                    if store.isLoading { ProgressView().controlSize(.small) }
                    else { Label("刷新", systemImage: "arrow.clockwise") }
                }
                .disabled(store.isLoading)

                Button {
                    exportDocument = MarkdownDocument(text: store.reportMarkdown)
                    isExporting = true
                } label: {
                    Label("导出本机报告", systemImage: "square.and.arrow.up")
                }
                .disabled(store.items.isEmpty)
            }

            Menu {
                Button("自定义识别规则…", systemImage: "text.badge.plus") { presentedSheet = .rules }
                Button("隐私与安全边界…", systemImage: "hand.raised") { presentedSheet = .privacy }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
        }
    }

    private var confirmationTitle: String {
        guard let action = store.pendingAction, let item = store.pendingItem else { return "确认操作" }
        return "\(action.title)“\(item.purpose.name)”？"
    }

    private var confirmationMessage: String {
        guard let action = store.pendingAction, let item = store.pendingItem else { return "" }
        if item.domain == .system { return "这是整台 Mac 的后台项，系统会要求管理员授权。不会删除应用或数据。" }
        if action == .stop { return "临时停止后，主应用或下次登录仍可能重新启动它。长期关闭请使用“禁用”。" }
        return "该操作不会删除应用、配置文件或用户数据。"
    }
}

private struct BackgroundItemSearchModifier: ViewModifier {
    @Binding var text: String
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, placement: .toolbar, prompt: "搜索名称、厂商、类别或 Label")
        } else {
            content
        }
    }
}

private enum AppSheet: String, Identifiable {
    case rules
    case privacy
    var id: String { rawValue }
}
