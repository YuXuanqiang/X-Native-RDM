import SwiftUI

struct ConnectionEditorView: View {
    @Bindable var store: ConnectionStore
    @State private var errorMessage: String?

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
                    TextField("数据库", text: draftBinding(\.database))
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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { store.editor = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 520)
    }

    private var title: String {
        switch store.editor?.mode {
        case .edit:
            "编辑连接"
        default:
            "新建连接"
        }
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<ConnectionDraft, Value>) -> Binding<Value> {
        Binding(
            get: { store.editor?.draft[keyPath: keyPath] ?? ConnectionDraft.default[keyPath: keyPath] },
            set: { newValue in
                guard var editor = store.editor else { return }
                editor.draft[keyPath: keyPath] = newValue
                store.editor = editor
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
        do {
            try store.saveEditor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
