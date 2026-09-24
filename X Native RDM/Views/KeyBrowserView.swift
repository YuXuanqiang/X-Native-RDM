import SwiftUI
import AppKit

struct KeyBrowserView: View {
    let profile: ConnectionProfile
    var session: RedisSession
    var store: ConnectionStore
    @State private var patternTask: Task<Void, Never>?
    @State private var pendingDeleteKey: String?

    var body: some View {
        @Bindable var browser = session.browser
        VStack(spacing: 0) {
            filterBar(browser)
            Divider()
            keyList(browser)
            footer(browser)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Keys")
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await session.reloadKeys() }
                }
                .disabled(browser.isScanning)
                .help("重新扫描 Key")
            }
            ToolbarItem(placement: .automatic) {
                Button("断开", role: .destructive) {
                    store.disconnect(profile)
                }
            }
        }
        .onChange(of: browser.pattern) { _, _ in
            scheduleReload()
        }
        .onChange(of: browser.separator) { _, _ in
            browser.rebuildTree()
        }
        .onChange(of: browser.selectedNodeID) { _, _ in
            if let key = browser.selectedRedisKey {
                Task { await session.inspectKey(key) }
            } else {
                browser.inspection = nil
            }
        }
        .onDisappear {
            patternTask?.cancel()
        }
        .confirmationDialog(
            "删除 Key",
            isPresented: Binding(
                get: { pendingDeleteKey != nil },
                set: { if !$0 { pendingDeleteKey = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let key = pendingDeleteKey {
                    Task { await session.deleteKey(key) }
                }
                pendingDeleteKey = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteKey = nil
            }
        } message: {
            if let key = pendingDeleteKey {
                Text("将删除 “\(key)”，此操作无法撤销。")
            }
        }
    }

    private func filterBar(_ browser: RedisKeyBrowser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("匹配，例如 user:*", text: Bindable(browser).pattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        patternTask?.cancel()
                        Task { await session.reloadKeys() }
                    }
                Picker("分隔符", selection: Bindable(browser).separator) {
                    Text(":").tag(":")
                    Text("/").tag("/")
                    Text(".").tag(".")
                    Text("无").tag("")
                }
                .labelsHidden()
                .frame(width: 56)
            }
            HStack {
                Text(profile.displayName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if profile.database == nil, let activeDatabase = session.activeDatabase {
                    Picker("数据库", selection: databaseSelection) {
                        ForEach(session.databaseOptions) { option in
                            if let keyCount = option.keyCount {
                                Text("DB \(option.index)（\(keyCount.formatted())）").tag(Optional(option.index))
                            } else {
                                Text("DB \(option.index)").tag(Optional(option.index))
                            }
                        }
                        if session.databaseOptions.isEmpty {
                            Text("DB \(activeDatabase)").tag(Optional(activeDatabase))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                Spacer()
                if browser.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text("扫描中 \(browser.scanProgress.formatted())")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(10)
        .task(id: session.activeDatabase) {
            if profile.database == nil, session.databaseOptions.isEmpty {
                await session.refreshDatabaseOptions()
            }
        }
    }

    private var databaseSelection: Binding<Int?> {
        Binding(
            get: { session.activeDatabase },
            set: { newValue in
                guard let newValue, newValue != session.activeDatabase else { return }
                Task { await session.selectDatabase(newValue) }
            }
        )
    }

    @ViewBuilder
    private func keyList(_ browser: RedisKeyBrowser) -> some View {
        Group {
            if !browser.isScanning && browser.roots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "key")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("没有 Key")
                        .font(.headline)
                    Text(browser.errorMessage ?? "当前匹配条件下没有数据")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 36)
                .padding(.horizontal, 16)
            } else {
                List(selection: Bindable(browser).selectedNodeID) {
                    OutlineGroup(browser.roots, children: \.children) { node in
                        KeyNodeRow(node: node)
                            .tag(node.id)
                            .contextMenu {
                                if let key = node.redisKey {
                                    Button("复制 Key") { copyToPasteboard(key) }
                                    Button("删除…", role: .destructive) {
                                        pendingDeleteKey = key
                                    }
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footer(_ browser: RedisKeyBrowser) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Text(summaryText(browser))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if browser.truncated {
                Text("仅加载前 \(RedisKeyBrowser.maxKeys.formatted()) 个 Key，请缩小匹配范围。")
                    .foregroundStyle(.orange)
            }
            if let errorMessage = browser.errorMessage, browser.inspection == nil {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func summaryText(_ browser: RedisKeyBrowser) -> String {
        var parts: [String] = []
        if let dbSize = browser.dbSize, let database = session.activeDatabase ?? profile.database {
            parts.append("DB \(database) · \(dbSize.formatted()) keys")
        } else if let dbSize = browser.dbSize {
            parts.append("\(dbSize.formatted()) keys")
        }
        parts.append("已加载 \(browser.scanProgress.formatted())")
        return parts.joined(separator: " · ")
    }

    private func scheduleReload() {
        patternTask?.cancel()
        patternTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await session.reloadKeys()
        }
    }
}

private struct KeyNodeRow: View {
    let node: KeyOutlineNode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isFolder ? "folder.fill" : "key.fill")
                .foregroundStyle(node.isFolder ? Color.accentColor.opacity(0.85) : .secondary)
                .font(.caption)
            Text(node.title)
                .lineLimit(1)
            Spacer()
            if node.isFolder {
                Text(node.descendantKeyCount.formatted())
                    .foregroundStyle(.tertiary)
                    .font(.caption2.monospacedDigit())
            }
        }
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
