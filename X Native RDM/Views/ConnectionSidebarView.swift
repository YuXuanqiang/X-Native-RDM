import AppKit
import SwiftUI

struct ConnectionSidebarView: View {
    @Bindable var store: ConnectionStore

    var body: some View {
        List(selection: $store.selectedID) {
            OutlineGroup(store.sidebarRoots, children: \.children) { node in
                sidebarRow(node)
                    .tag(node.id)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .listRowBackground(FinderSidebarSelection(isSelected: store.selectedID == node.id))
                    .contextMenu { contextMenu(for: node) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 12, for: .scrollContent)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, 10)
        .tint(.primary)
        .background(DisableSystemListHighlight())
        .navigationTitle("连接")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("新建连接", systemImage: "plus") {
                        store.beginCreate()
                    }
                    Button("新建目录", systemImage: "folder.badge.plus") {
                        store.beginCreateFolder()
                    }
                    if let folder = store.selectedFolder {
                        Button("在“\(folder.displayName)”下新建子目录") {
                            store.beginCreateFolder(parentID: folder.id)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("新建连接或目录")
            }
        }
        .onChange(of: store.selectedID) { _, _ in
            store.persistSelection()
        }
        .onDeleteCommand {
            if let profile = store.selectedProfile {
                store.requestDelete(profile)
            } else if let folder = store.selectedFolder {
                store.requestDeleteFolder(folder)
            }
        }
        .overlay {
            if store.isEmpty {
                ContentUnavailableView(
                    "还没有内容",
                    systemImage: "folder",
                    description: Text("用右上角加号创建目录，或直接添加 Redis 连接")
                )
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ node: ConnectionSidebarNode) -> some View {
        if let folder = node.folder {
            FolderRowView(folder: folder, profileCount: profileCount(in: node))
        } else if let profile = node.profile {
            ConnectionRowView(profile: profile, session: store.session(for: profile.id))
        }
    }

    @ViewBuilder
    private func contextMenu(for node: ConnectionSidebarNode) -> some View {
        if let folder = node.folder {
            Button("新建连接") { store.beginCreate(in: folder.id) }
            Button("新建子目录") { store.beginCreateFolder(parentID: folder.id) }
            Divider()
            Button("重命名…") { store.beginRenameFolder(folder) }
            moveMenu(for: node)
            Divider()
            Button("删除…", role: .destructive) { store.requestDeleteFolder(folder) }
        } else if let profile = node.profile {
            Button("连接") { store.connect(profile) }
            Button("断开") { store.disconnect(profile) }
            Divider()
            Button("编辑…") { store.beginEdit(profile) }
            Button("复制") { store.duplicate(profile) }
            moveMenu(for: node)
            Divider()
            Button("删除…", role: .destructive) { store.requestDelete(profile) }
        }
    }

    private func profileCount(in node: ConnectionSidebarNode) -> Int {
        (node.children ?? []).reduce(0) { total, child in
            child.profile != nil ? total + 1 : total + profileCount(in: child)
        }
    }

    @ViewBuilder
    private func moveMenu(for node: ConnectionSidebarNode) -> some View {
        let destinations = store.moveDestinations(for: node)
        let showsRoot = store.canMoveToRoot(node)
        Menu("移动") {
            if showsRoot {
                Button("根目录") { store.move(node, to: nil) }
            }
            if showsRoot && !destinations.isEmpty {
                Divider()
            }
            ForEach(destinations) { option in
                Button(option.path) { store.move(node, to: option.id) }
            }
            if !showsRoot && destinations.isEmpty {
                Button("没有可移动的目录") {}
                    .disabled(true)
            }
        }
    }
}

private struct FolderRowView: View {
    let folder: ConnectionFolder
    let profileCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .symbolRenderingMode(.multicolor)
                .frame(width: 16, height: 16)
            Text(folder.displayName)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if profileCount > 0 {
                Text("\(profileCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct ConnectionRowView: View {
    let profile: ConnectionProfile
    var session: RedisSession

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            statusIndicator
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(profile.endpointText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch session.status {
        case .connecting:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
        default:
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .frame(width: 16, height: 16)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .connected:
            .green
        case .failed:
            .red
        case .connecting:
            .orange
        case .disconnected:
            Color(nsColor: .tertiaryLabelColor)
        }
    }
}

private struct FinderSidebarSelection: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
    }
}

private struct DisableSystemListHighlight: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HighlightInstallerView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HighlightInstallerView)?.install()
    }
}

private final class HighlightInstallerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        install()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        install()
    }

    func install() {
        DispatchQueue.main.async { [weak self] in
            self?.disableHighlight()
        }
    }

    private func disableHighlight() {
        var current: NSView? = superview
        while let view = current {
            if let table = view as? NSTableView {
                table.selectionHighlightStyle = .none
                return
            }
            current = view.superview
        }
    }
}
