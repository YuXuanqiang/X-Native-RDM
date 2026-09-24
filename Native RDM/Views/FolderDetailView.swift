import SwiftUI

struct FolderDetailView: View {
    let folder: ConnectionFolder
    var store: ConnectionStore

    var body: some View {
        let counts = store.descendantCounts(for: folder)
        ContentUnavailableView {
            Label(folder.displayName, systemImage: "folder.fill")
        } description: {
            VStack(spacing: 8) {
                Text(store.folderPath(folder.id))
                Text(summary(counts))
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button("新建连接") {
                store.beginCreate(in: folder.id)
            }
            Button("新建子目录") {
                store.beginCreateFolder(parentID: folder.id)
            }
        }
        .navigationTitle(folder.displayName)
    }

    private func summary(_ counts: (folders: Int, profiles: Int)) -> String {
        let folderText = counts.folders == 0 ? "没有子目录" : "\(counts.folders) 个子目录"
        let profileText = counts.profiles == 0 ? "没有连接" : "\(counts.profiles) 个连接"
        return "\(folderText) · \(profileText)"
    }
}
