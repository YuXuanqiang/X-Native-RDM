import Foundation

nonisolated struct RedisHandshake: Sendable {
    var protocolVersion: Int
    var server: String
    var version: String?
    var mode: String?
    var role: String?

    var summary: String {
        var parts = ["已连接"]
        parts.append(server)
        if let version, !version.isEmpty {
            parts.append(version)
        }
        parts.append("RESP\(protocolVersion)")
        if let role, !role.isEmpty {
            parts.append(role)
        }
        return parts.joined(separator: " · ")
    }
}

extension RESPValue {
    func handshakeInfo() -> RedisHandshake {
        let proto = intField("proto") ?? 3
        let server = stringField("server") ?? "Redis"
        return RedisHandshake(
            protocolVersion: Int(proto),
            server: server,
            version: stringField("version"),
            mode: stringField("mode"),
            role: stringField("role")
        )
    }

    func stringField(_ key: String) -> String? {
        field(key)?.stringContent
    }

    func intField(_ key: String) -> Int64? {
        guard let value = field(key) else { return nil }
        if case .integer(let number) = value {
            return number
        }
        return value.stringContent.flatMap(Int64.init)
    }

    func field(_ key: String) -> RESPValue? {
        let needle = key.lowercased()
        switch self {
        case .map(let entries):
            return entries.first { $0.key.stringContent?.lowercased() == needle }?.value
        case .array(let items?):
            var index = 0
            while index + 1 < items.count {
                if items[index].stringContent?.lowercased() == needle {
                    return items[index + 1]
                }
                index += 2
            }
            return nil
        default:
            return nil
        }
    }
}
