import Foundation

nonisolated struct ConnectionProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var database: Int
    var useTLS: Bool
    var verifyTLSCertificate: Bool
    var connectTimeout: TimeInterval
    var createdAt: Date
    var updatedAt: Date
    var folderID: UUID?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, database, useTLS, verifyTLSCertificate
        case connectTimeout, createdAt, updatedAt, folderID, sortOrder
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? endpointText : trimmed
    }

    var endpointText: String {
        "\(host):\(port)"
    }

    init(
        id: UUID,
        name: String,
        host: String,
        port: Int,
        username: String,
        database: Int,
        useTLS: Bool,
        verifyTLSCertificate: Bool,
        connectTimeout: TimeInterval,
        createdAt: Date,
        updatedAt: Date,
        folderID: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.useTLS = useTLS
        self.verifyTLSCertificate = verifyTLSCertificate
        self.connectTimeout = connectTimeout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.folderID = folderID
        self.sortOrder = sortOrder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(database, forKey: .database)
        try container.encode(useTLS, forKey: .useTLS)
        try container.encode(verifyTLSCertificate, forKey: .verifyTLSCertificate)
        try container.encode(connectTimeout, forKey: .connectTimeout)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        database = try container.decode(Int.self, forKey: .database)
        useTLS = try container.decode(Bool.self, forKey: .useTLS)
        verifyTLSCertificate = try container.decodeIfPresent(Bool.self, forKey: .verifyTLSCertificate) ?? true
        connectTimeout = try container.decode(TimeInterval.self, forKey: .connectTimeout)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    static func makeDefault(folderID: UUID? = nil) -> ConnectionProfile {
        let now = Date()
        return ConnectionProfile(
            id: UUID(),
            name: "本地 Redis",
            host: "127.0.0.1",
            port: 6379,
            username: "",
            database: 0,
            useTLS: false,
            verifyTLSCertificate: true,
            connectTimeout: 5,
            createdAt: now,
            updatedAt: now,
            folderID: folderID
        )
    }
}

nonisolated struct ConnectionDraft: Equatable {
    var name: String
    var host: String
    var port: String
    var username: String
    var password: String
    var database: String
    var useTLS: Bool
    var verifyTLSCertificate: Bool
    var connectTimeout: String

    static func from(_ profile: ConnectionProfile, password: String) -> ConnectionDraft {
        ConnectionDraft(
            name: profile.name,
            host: profile.host,
            port: String(profile.port),
            username: profile.username,
            password: password,
            database: String(profile.database),
            useTLS: profile.useTLS,
            verifyTLSCertificate: profile.verifyTLSCertificate,
            connectTimeout: String(Int(profile.connectTimeout))
        )
    }

    static var `default`: ConnectionDraft {
        from(.makeDefault(), password: "")
    }

    func validatedProfile(id: UUID, createdAt: Date, folderID: UUID?, sortOrder: Int) throws -> ConnectionProfile {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw ValidationError("请填写主机地址") }

        guard let port = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) else {
            throw ValidationError("端口必须是 1 到 65535 之间的整数")
        }

        guard let database = Int(database.trimmingCharacters(in: .whitespacesAndNewlines)), database >= 0 else {
            throw ValidationError("数据库索引必须是大于等于 0 的整数")
        }

        guard let timeout = TimeInterval(connectTimeout.trimmingCharacters(in: .whitespacesAndNewlines)), timeout >= 1, timeout <= 60 else {
            throw ValidationError("连接超时必须是 1 到 60 秒")
        }

        var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = "\(host):\(port)"
        }

        return ConnectionProfile(
            id: id,
            name: name,
            host: host,
            port: port,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            database: database,
            useTLS: useTLS,
            verifyTLSCertificate: verifyTLSCertificate,
            connectTimeout: timeout,
            createdAt: createdAt,
            updatedAt: Date(),
            folderID: folderID,
            sortOrder: sortOrder
        )
    }
}

nonisolated struct ValidationError: Error, LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
