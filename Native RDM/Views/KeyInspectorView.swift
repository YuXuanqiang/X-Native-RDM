import SwiftUI
import AppKit

struct KeyInspectorView: View {
    var session: RedisSession
    @State private var pendingDelete = false
    @State private var commandText = "PING"

    var body: some View {
        @Bindable var browser = session.browser
        Group {
            if browser.isInspecting && browser.inspection == nil {
                ProgressView("正在加载…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let inspection = browser.inspection {
                inspector(inspection, browser: browser)
            } else {
                ContentUnavailableView(
                    "选择一个 Key",
                    systemImage: "key",
                    description: Text("从左侧树中选择 Key，查看类型、TTL 和值")
                )
            }
        }
        .navigationTitle(browser.inspection?.key ?? "值")
        .confirmationDialog("删除 Key", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let key = browser.inspection?.key {
                    Task { await session.deleteKey(key) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let key = browser.inspection?.key {
                Text("将删除 “\(key)”，此操作无法撤销。")
            }
        }
    }

    private func inspector(_ inspection: RedisKeyInspection, browser: RedisKeyBrowser) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(inspection)
            Divider()
            valuePane(inspection, browser: browser)
            Divider()
            commandBar
            if !session.lastResponse.isEmpty {
                ScrollView {
                    Text(session.lastResponse)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                .frame(maxHeight: 90)
            }
        }
    }

    private func header(_ inspection: RedisKeyInspection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(inspection.type.title, systemImage: inspection.type.icon)
                    .font(.headline)
                Spacer()
                Button("复制 Key") { copyToPasteboard(inspection.key) }
                Button("刷新") {
                    Task { await session.inspectKey(inspection.key) }
                }
                Button("删除", role: .destructive) { pendingDelete = true }
            }
            Text(inspection.key)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            HStack(spacing: 16) {
                meta("TTL", inspection.ttlText)
                meta("长度", inspection.cardinalityText)
                meta("内存", inspection.memoryText)
            }
            .font(.caption)
            if inspection.truncated {
                Text(truncatedMessage(for: inspection))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let errorMessage = session.browser.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func valuePane(_ inspection: RedisKeyInspection, browser: RedisKeyBrowser) -> some View {
        switch inspection.value {
        case .empty:
            ContentUnavailableView("Key 不存在", systemImage: "questionmark.square")
        case .string(let text, let binary):
            stringPane(text: text, binary: binary, browser: browser)
        case .table(let table):
            Table(table.rows) {
                TableColumn(table.primaryTitle, value: \.primary)
                    .width(min: 60, ideal: 120)
                TableColumn(table.secondaryTitle, value: \.secondary)
            }
        case .raw(let text):
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
    }

    private func stringPane(text: String, binary: Bool, browser: RedisKeyBrowser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if binary {
                Text("二进制数据，无法直接编辑")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                TextEditor(text: Bindable(browser).editedString)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                HStack {
                    Spacer()
                    Button("保存") {
                        Task { await session.saveStringValue() }
                    }
                    .disabled(!browser.canSaveString)
                    .keyboardShortcut("s")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }

    private var commandBar: some View {
        HStack {
            TextField("命令，例如 GET mykey", text: $commandText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendCommand() }
            Button("执行") { sendCommand() }
        }
        .padding(12)
    }

    private func meta(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func truncatedMessage(for inspection: RedisKeyInspection) -> String {
        if case .string = inspection.value {
            return "内容已截断，仅预览前 \(RedisKeyBrowser.stringPreviewBytes / 1024) KB。"
        }
        return "内容已截断，仅显示前 \(RedisKeyBrowser.collectionPage) 条。"
    }

    private func sendCommand() {
        let tokens = RedisCommandLine.tokenize(commandText)
        Task { await session.run(tokens) }
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
