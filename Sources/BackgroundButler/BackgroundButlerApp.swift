import SwiftUI

@main
struct BackgroundButlerApp: App {
    @StateObject private var store = AppStore(historyStore: SnapshotHistoryStore())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("刷新后台项") { Task { await store.reload() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("本机总览") { store.selectFilter(.overview) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("全部后台项") { store.selectFilter(.all) }
                    .keyboardShortcut("2", modifiers: .command)
            }
        }
    }
}
