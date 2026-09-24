import Foundation

nonisolated struct ConnectionFolder: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var parentID: UUID?
    var sortOrder: Int
    var createdAt: Date

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名目录" : trimmed
    }
}

nonisolated struct ConnectionLibrary: Codable, Sendable {
    var folders: [ConnectionFolder]
    var profiles: [ConnectionProfile]
}

nonisolated struct ConnectionSidebarNode: Identifiable, Hashable, Sendable {
    var id: UUID
    var folder: ConnectionFolder?
    var profile: ConnectionProfile?
    var children: [ConnectionSidebarNode]?

    var isFolder: Bool { folder != nil }
}

nonisolated struct FolderOption: Identifiable, Hashable, Sendable {
    var id: UUID
    var path: String
}
