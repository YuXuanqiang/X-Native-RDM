import Foundation
import SwiftUI

@Observable
final class ConnectionStore {
    var folders: [ConnectionFolder] = []
    var profiles: [ConnectionProfile] = []
    var selectedID: UUID?
    var editor: EditorState?
    var folderEditor: FolderEditorState?
    var pendingDeletion: PendingDeletion?

    private(set) var sessions: [UUID: RedisSession] = [:]
    private let selectedIDKey = "selectedConnectionID"

    struct EditorState: Identifiable, Equatable {
        enum Mode: Equatable {
            case create
            case edit(UUID)
        }

        let id = UUID()
        var mode: Mode
        var draft: ConnectionDraft
        var folderID: UUID?
    }

    struct FolderEditorState: Identifiable, Equatable {
        enum Mode: Equatable {
            case create
            case rename(UUID)
        }

        let id = UUID()
        var mode: Mode
        var name: String
        var parentID: UUID?
    }

    enum PendingDeletion {
        case profile(ConnectionProfile)
        case folder(ConnectionFolder)
    }

    init() {
        let library = ConnectionProfileStore.load()
        folders = library.folders
        profiles = library.profiles

        let validIDs = Set(profiles.map(\.id) + folders.map(\.id))
        if let raw = UserDefaults.standard.string(forKey: selectedIDKey),
           let id = UUID(uuidString: raw),
           validIDs.contains(id) {
            selectedID = id
        } else {
            selectedID = profiles.first?.id ?? folders.first?.id
        }
        for profile in profiles {
            sessions[profile.id] = RedisSession()
        }
    }

    var selectedProfile: ConnectionProfile? {
        profiles.first { $0.id == selectedID }
    }

    var selectedFolder: ConnectionFolder? {
        folders.first { $0.id == selectedID }
    }

    var sidebarRoots: [ConnectionSidebarNode] {
        nodes(in: nil)
    }

    var folderOptions: [FolderOption] {
        availableParentFolders()
    }

    func availableParentFolders(excluding folderID: UUID? = nil) -> [FolderOption] {
        let excluded = folderID.map { descendantFolderIDs(of: $0) } ?? []
        return folders
            .filter { !excluded.contains($0.id) }
            .map { FolderOption(id: $0.id, path: folderPath($0.id)) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    var isEmpty: Bool {
        profiles.isEmpty && folders.isEmpty
    }

    func session(for id: UUID) -> RedisSession {
        if let session = sessions[id] {
            return session
        }
        let session = RedisSession()
        sessions[id] = session
        return session
    }

    func beginCreate(in folderID: UUID? = nil) {
        editor = EditorState(
            mode: .create,
            draft: .default,
            folderID: folderID ?? insertionFolderID
        )
    }

    func beginEdit(_ profile: ConnectionProfile) {
        editor = EditorState(
            mode: .edit(profile.id),
            draft: .from(profile, password: KeychainPasswordStore.password(for: profile.id)),
            folderID: profile.folderID
        )
    }

    func beginCreateFolder(parentID: UUID? = nil) {
        folderEditor = FolderEditorState(
            mode: .create,
            name: "新建目录",
            parentID: parentID ?? insertionFolderID
        )
    }

    func beginRenameFolder(_ folder: ConnectionFolder) {
        folderEditor = FolderEditorState(
            mode: .rename(folder.id),
            name: folder.name,
            parentID: folder.parentID
        )
    }

    func saveEditor() throws {
        guard let editor else { return }
        switch editor.mode {
        case .create:
            let profile = try editor.draft.validatedProfile(
                id: UUID(),
                createdAt: Date(),
                folderID: editor.folderID,
                sortOrder: nextProfileSortOrder(in: editor.folderID)
            )
            try KeychainPasswordStore.setPassword(editor.draft.password, for: profile.id)
            profiles.append(profile)
            sessions[profile.id] = RedisSession()
            selectedID = profile.id
        case .edit(let id):
            guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
            let profile = try editor.draft.validatedProfile(
                id: id,
                createdAt: profiles[index].createdAt,
                folderID: editor.folderID,
                sortOrder: profiles[index].sortOrder
            )
            try KeychainPasswordStore.setPassword(editor.draft.password, for: id)
            profiles[index] = profile
            selectedID = id
        }
        persist()
        self.editor = nil
    }

    func saveFolderEditor() throws {
        guard let folderEditor else { return }
        let name = folderEditor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError("请填写目录名称") }

        switch folderEditor.mode {
        case .create:
            try validateParent(folderEditor.parentID)
            let folder = ConnectionFolder(
                id: UUID(),
                name: name,
                parentID: folderEditor.parentID,
                sortOrder: nextFolderSortOrder(in: folderEditor.parentID),
                createdAt: Date()
            )
            folders.append(folder)
            selectedID = folder.id
        case .rename(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            try validateParent(folderEditor.parentID, excluding: id)
            folders[index].name = name
            folders[index].parentID = folderEditor.parentID
            selectedID = id
        }
        persist()
        self.folderEditor = nil
    }

    func duplicate(_ profile: ConnectionProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = profile.name.hasSuffix(" 副本") ? profile.name : "\(profile.displayName) 副本"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.sortOrder = nextProfileSortOrder(in: profile.folderID)
        try? KeychainPasswordStore.setPassword(KeychainPasswordStore.password(for: profile.id), for: copy.id)
        profiles.append(copy)
        sessions[copy.id] = RedisSession()
        selectedID = copy.id
        persist()
    }

    func requestDelete(_ profile: ConnectionProfile) {
        pendingDeletion = .profile(profile)
    }

    func requestDeleteFolder(_ folder: ConnectionFolder) {
        pendingDeletion = .folder(folder)
    }

    func confirmDelete() {
        switch pendingDeletion {
        case .profile(let profile):
            deleteProfile(profile)
        case .folder(let folder):
            deleteFolder(folder)
        case nil:
            break
        }
        pendingDeletion = nil
        persist()
    }

    func connect(_ profile: ConnectionProfile) {
        selectedID = profile.id
        session(for: profile.id).connect(
            profile: profile,
            password: KeychainPasswordStore.password(for: profile.id)
        )
    }

    func disconnect(_ profile: ConnectionProfile) {
        session(for: profile.id).disconnect()
    }

    func persistSelection() {
        if let selectedID {
            UserDefaults.standard.set(selectedID.uuidString, forKey: selectedIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedIDKey)
        }
    }

    func folderPath(_ id: UUID) -> String {
        var names: [String] = []
        var currentID: UUID? = id
        var seen = Set<UUID>()
        while let folderID = currentID, seen.insert(folderID).inserted {
            guard let folder = folders.first(where: { $0.id == folderID }) else { break }
            names.insert(folder.displayName, at: 0)
            currentID = folder.parentID
        }
        return names.joined(separator: " / ")
    }

    func descendantCounts(for folder: ConnectionFolder) -> (folders: Int, profiles: Int) {
        let ids = descendantFolderIDs(of: folder.id)
        return (
            folders: ids.count - 1,
            profiles: profiles.filter { profile in
                guard let folderID = profile.folderID else { return false }
                return ids.contains(folderID)
            }.count
        )
    }

    private var insertionFolderID: UUID? {
        if let selectedFolder {
            return selectedFolder.id
        }
        return selectedProfile?.folderID
    }

    private func nodes(in parentID: UUID?) -> [ConnectionSidebarNode] {
        let folderNodes = folders
            .filter { $0.parentID == parentID }
            .sorted(by: Self.folderSort)
            .map { folder in
                ConnectionSidebarNode(
                    id: folder.id,
                    folder: folder,
                    profile: nil,
                    children: nodes(in: folder.id)
                )
            }
        let profileNodes = profiles
            .filter { $0.folderID == parentID }
            .sorted(by: Self.profileSort)
            .map { profile in
                ConnectionSidebarNode(
                    id: profile.id,
                    folder: nil,
                    profile: profile,
                    children: nil
                )
            }
        return folderNodes + profileNodes
    }

    private func nextFolderSortOrder(in parentID: UUID?) -> Int {
        (folders.filter { $0.parentID == parentID }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func nextProfileSortOrder(in folderID: UUID?) -> Int {
        (profiles.filter { $0.folderID == folderID }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func deleteProfile(_ profile: ConnectionProfile) {
        session(for: profile.id).disconnect()
        sessions[profile.id] = nil
        KeychainPasswordStore.deletePassword(for: profile.id)
        profiles.removeAll { $0.id == profile.id }
        if selectedID == profile.id {
            selectedID = profiles.first?.id ?? folders.first?.id
        }
    }

    private func deleteFolder(_ folder: ConnectionFolder) {
        let folderIDs = descendantFolderIDs(of: folder.id)
        let removedProfiles = profiles.filter { profile in
            guard let folderID = profile.folderID else { return false }
            return folderIDs.contains(folderID)
        }
        removedProfiles.forEach(deleteProfile)
        folders.removeAll { folderIDs.contains($0.id) }
        if let selectedID, folderIDs.contains(selectedID) {
            self.selectedID = profiles.first?.id ?? folders.first?.id
        }
    }

    private func validateParent(_ parentID: UUID?, excluding folderID: UUID? = nil) throws {
        guard let parentID else { return }
        guard folders.contains(where: { $0.id == parentID }) else {
            throw ValidationError("上级目录不存在")
        }
        if let folderID, descendantFolderIDs(of: folderID).contains(parentID) {
            throw ValidationError("不能把目录移动到自身或子目录下")
        }
    }

    private func descendantFolderIDs(of id: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [id]
        var pending = [id]
        while let current = pending.popLast() {
            let children = folders.filter { $0.parentID == current }.map(\.id)
            for child in children where ids.insert(child).inserted {
                pending.append(child)
            }
        }
        return ids
    }

    private func persist() {
        persistSelection()
        try? ConnectionProfileStore.save(ConnectionLibrary(folders: folders, profiles: profiles))
    }

    private static func folderSort(_ lhs: ConnectionFolder, _ rhs: ConnectionFolder) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func profileSort(_ lhs: ConnectionProfile, _ rhs: ConnectionProfile) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }
}
