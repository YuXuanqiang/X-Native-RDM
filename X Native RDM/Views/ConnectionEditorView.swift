import SwiftUI
import AppKit

struct ConnectionEditorView: View {
    @Bindable var store: ConnectionStore
    @State private var errorMessage: String?
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var testTask: Task<Void, Never>?
    @State private var showTestDetail = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: draftBinding(\.name))
                    Picker("目录", selection: folderBinding) {
                        Text("根目录").tag(Optional<UUID>.none)
                        ForEach(store.folderOptions) { option in
                            Text(option.path).tag(Optional(option.id))
                        }
                    }
                    TextField("主机", text: draftBinding(\.host))
                    TextField("端口", text: draftBinding(\.port))
                    TextField("数据库（可选）", text: draftBinding(\.database))
                        .help("填写后连接时直接进入该库；留空则连接后手动选择")
                }

                Section("认证") {
                    TextField("用户名", text: draftBinding(\.username))
                    SecureField("密码", text: draftBinding(\.password))
                }

                Section("安全与超时") {
                    Toggle("使用 TLS", isOn: draftBinding(\.useTLS))
                    Toggle("校验证书", isOn: draftBinding(\.verifyTLSCertificate))
                        .disabled(!(store.editor?.draft.useTLS ?? false))
                    TextField("连接超时（秒）", text: draftBinding(\.connectTimeout))
                }

                Section("连接测试") {
                    HStack(spacing: 8) {
                        Button("测试连接") {
                            testConnection()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .disabled(isTesting)

                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else if let testResult {
                            Button {
                                showTestDetail.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(testResult.shortLabel)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showTestDetail, arrowEdge: .bottom) {
                                testDetailPopover(testResult)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        testTask?.cancel()
                        store.editor = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isTesting)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 560)
        .onDisappear {
            testTask?.cancel()
            testTask = nil
        }
    }

    private var title: String {
        switch store.editor?.mode {
        case .edit:
            "编辑连接"
        default:
            "新建连接"
        }
    }

    @ViewBuilder
    private func testDetailPopover(_ result: ConnectionTestResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已成功")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.copyText, forType: .string)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(result.dbmsLine)
                if let modeLine = result.modeLine {
                    Text(modeLine)
                }
                Text(result.protocolLine)
                if let roleLine = result.roleLine {
                    Text(roleLine)
                }
                Text(result.pingLine)
            }
            .font(.callout)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
        }
        .padding(14)
        .frame(minWidth: 280, alignment: .leading)
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<ConnectionDraft, Value>) -> Binding<Value> {
        Binding(
            get: { store.editor?.draft[keyPath: keyPath] ?? ConnectionDraft.default[keyPath: keyPath] },
            set: { newValue in
                guard var editor = store.editor else { return }
                editor.draft[keyPath: keyPath] = newValue
                store.editor = editor
                clearStatus()
            }
        )
    }

    private var folderBinding: Binding<UUID?> {
        Binding(
            get: { store.editor?.folderID },
            set: { newValue in
                guard var editor = store.editor else { return }
                editor.folderID = newValue
                store.editor = editor
            }
        )
    }

    private func save() {
        clearStatus()
        do {
            try store.saveEditor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func testConnection() {
        guard let editor = store.editor else { return }
        clearStatus()

        let profile: ConnectionProfile
        do {
            profile = try editor.draft.validatedProfile(
                id: UUID(),
                createdAt: Date(),
                folderID: editor.folderID,
                sortOrder: 0
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let password = editor.draft.password
        isTesting = true
        testTask?.cancel()
        testTask = Task {
            let client = RedisClient()
            do {
                let handshake = try await client.connect(
                    host: profile.host,
                    port: profile.port,
                    username: profile.username,
                    password: password,
                    database: profile.database,
                    useTLS: profile.useTLS,
                    verifyTLSCertificate: profile.verifyTLSCertificate,
                    timeout: Duration.seconds(max(1, profile.connectTimeout))
                )
                let started = ContinuousClock().now
                _ = try await client.execute(RedisCommand.ping(), timeout: Duration.seconds(max(1, profile.connectTimeout)))
                let ping = ContinuousClock().now - started
                await client.disconnect(sendQuit: true)
                guard !Task.isCancelled else { return }
                testResult = ConnectionTestResult(handshake: handshake, ping: ping)
                isTesting = false
            } catch is CancellationError {
                isTesting = false
            } catch {
                await client.disconnect(sendQuit: false)
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isTesting = false
            }
        }
    }

    private func clearStatus() {
        errorMessage = nil
        testResult = nil
        showTestDetail = false
    }
}

private struct ConnectionTestResult {
    let handshake: RedisHandshake
    let pingMilliseconds: Int

    init(handshake: RedisHandshake, ping: Duration) {
        self.handshake = handshake
        let (seconds, attoseconds) = ping.components
        pingMilliseconds = max(0, Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000))
    }

    var shortLabel: String {
        let name = handshake.server.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = name.isEmpty ? "Redis" : name.prefix(1).uppercased() + name.dropFirst()
        if let version = handshake.version, !version.isEmpty {
            return "\(server) \(version)"
        }
        return server
    }

    var dbmsLine: String {
        var title = handshake.server.isEmpty ? "Redis" : handshake.server
        if let mode = handshake.mode?.lowercased(), mode.contains("cluster") {
            title = "Redis Cluster"
        } else if title.lowercased() == "redis" {
            title = "Redis"
        }
        if let version = handshake.version, !version.isEmpty {
            return "DBMS: \(title)（版本 \(version)）"
        }
        return "DBMS: \(title)"
    }

    var modeLine: String? {
        guard let mode = handshake.mode, !mode.isEmpty else { return nil }
        return "模式: \(mode)"
    }

    var protocolLine: String {
        "协议: RESP\(handshake.protocolVersion)"
    }

    var roleLine: String? {
        guard let role = handshake.role, !role.isEmpty else { return nil }
        return "角色: \(role)"
    }

    var pingLine: String {
        "Ping: \(pingMilliseconds)毫秒"
    }

    var copyText: String {
        [dbmsLine, modeLine, protocolLine, roleLine, pingLine]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}
