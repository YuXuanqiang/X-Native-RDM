import SwiftUI

struct ContentView: View {
    @Environment(ConnectionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            ConnectionSidebarView(store: store)
        } content: {
            middleColumn
        } detail: {
            detailColumn
        }
        .frame(minWidth: 960, minHeight: 580)
        .sheet(item: $store.editor) { _ in
            ConnectionEditorView(store: store)
        }
        .sheet(item: $store.folderEditor) { _ in
            FolderEditorView(store: store)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                store.confirmDelete()
            }
            Button("取消", role: .cancel) {
                store.pendingDeletion = nil
            }
        } message: {
            Text(deletionMessage)
        }
    }

    @ViewBuilder
    private var middleColumn: some View {
        if let profile = store.selectedProfile {
            let session = store.session(for: profile.id)
            if session.isConnected {
                if session.activeDatabase != nil {
                    KeyBrowserView(profile: profile, session: session, store: store)
                } else {
                    DatabasePickerView(profile: profile, session: session, store: store)
                }
            } else {
                ConnectionDetailView(profile: profile, session: session, store: store)
            }
        } else if let folder = store.selectedFolder {
            FolderDetailView(folder: folder, store: store)
        } else {
            ContentUnavailableView(
                "X Native RDM",
                systemImage: "cylinder.split.1x2",
                description: Text("选择目录或 Redis 连接，也可以新建一个")
            )
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let profile = store.selectedProfile {
            let session = store.session(for: profile.id)
            if session.isConnected, session.activeDatabase != nil {
                KeyInspectorView(session: session)
            } else if session.isConnected {
                ContentUnavailableView(
                    "选择数据库",
                    systemImage: "cylinder.split.1x2",
                    description: Text("在中间栏选择要浏览的 Redis 数据库")
                )
            } else {
                ContentUnavailableView(
                    "连接后浏览 Key",
                    systemImage: "key",
                    description: Text("先在中间栏连接到 Redis，然后扫描并查看 Key")
                )
            }
        } else if store.selectedFolder != nil {
            ContentUnavailableView(
                "选择一个连接",
                systemImage: "cylinder.split.1x2",
                description: Text("目录用于组织连接，选中某个 Redis 连接后再浏览 Key")
            )
        } else {
            Color.clear
        }
    }

    private var deletionTitle: String {
        switch store.pendingDeletion {
        case .folder:
            "删除目录"
        default:
            "删除连接"
        }
    }

    private var deletionMessage: String {
        switch store.pendingDeletion {
        case .profile(let profile):
            return "将删除“\(profile.displayName)”，此操作无法撤销。"
        case .folder(let folder):
            let counts = store.descendantCounts(for: folder)
            if counts.folders == 0 && counts.profiles == 0 {
                return "将删除空目录“\(folder.displayName)”。"
            }
            return "将删除目录“\(folder.displayName)”及其下的 \(counts.folders) 个子目录、\(counts.profiles) 个连接。此操作无法撤销。"
        case nil:
            return ""
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { store.pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    store.pendingDeletion = nil
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .environment(ConnectionStore())
}
