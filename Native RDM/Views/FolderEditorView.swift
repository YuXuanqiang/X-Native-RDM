import SwiftUI

struct FolderEditorView: View {
    @Bindable var store: ConnectionStore
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("目录") {
                    TextField("名称", text: nameBinding)
                    Picker("上级", selection: parentBinding) {
                        Text("根目录").tag(Optional<UUID>.none)
                        ForEach(parentOptions) { option in
                            Text(option.path).tag(Optional(option.id))
                        }
                    }
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
                    Button("取消") { store.folderEditor = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 240)
    }

    private var title: String {
        switch store.folderEditor?.mode {
        case .rename:
            "重命名目录"
        case .create, .none:
            "新建目录"
        }
    }

    private var parentOptions: [FolderOption] {
        if case .rename(let id) = store.folderEditor?.mode {
            return store.availableParentFolders(excluding: id)
        }
        return store.availableParentFolders()
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.folderEditor?.name ?? "" },
            set: { newValue in
                guard var editor = store.folderEditor else { return }
                editor.name = newValue
                store.folderEditor = editor
            }
        )
    }

    private var parentBinding: Binding<UUID?> {
        Binding(
            get: { store.folderEditor?.parentID },
            set: { newValue in
                guard var editor = store.folderEditor else { return }
                editor.parentID = newValue
                store.folderEditor = editor
            }
        )
    }

    private func save() {
        do {
            try store.saveFolderEditor()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
