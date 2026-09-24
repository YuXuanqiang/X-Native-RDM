import SwiftUI

@main
struct XNativeRDMApp: App {
    @State private var store = ConnectionStore()

    var body: some Scene {
        WindowGroup("X Native RDM") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建连接…") {
                    store.beginCreate()
                }
                .keyboardShortcut("n")
                Button("新建目录…") {
                    store.beginCreateFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }
    }
}
