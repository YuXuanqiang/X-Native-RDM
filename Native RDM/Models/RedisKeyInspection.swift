import Foundation

nonisolated enum RedisKeyType: Sendable, Hashable {
    case string
    case list
    case set
    case zset
    case hash
    case stream
    case json
    case none
    case other(String)

    init(serverType: String) {
        switch serverType.lowercased() {
        case "string": self = .string
        case "list": self = .list
        case "set": self = .set
        case "zset": self = .zset
        case "hash": self = .hash
        case "stream": self = .stream
        case "rejson-rl", "json": self = .json
        case "none": self = .none
        default: self = .other(serverType)
        }
    }

    var title: String {
        switch self {
        case .string: "String"
        case .list: "List"
        case .set: "Set"
        case .zset: "ZSet"
        case .hash: "Hash"
        case .stream: "Stream"
        case .json: "JSON"
        case .none: "None"
        case .other(let raw): raw
        }
    }

    var icon: String {
        switch self {
        case .string: "text.alignleft"
        case .list: "list.number"
        case .set: "circle.grid.2x2"
        case .zset: "chart.bar"
        case .hash: "tablecells"
        case .stream: "water.waves"
        case .json: "curlybraces"
        case .none: "questionmark"
        case .other: "questionmark.square"
        }
    }
}

nonisolated struct RedisFieldRow: Identifiable, Hashable, Sendable {
    var id: Int
    var primary: String
    var secondary: String
}

nonisolated enum RedisDecodedValue: Sendable {
    case empty
    case string(text: String, binary: Bool)
    case table(RedisTableValue)
    case raw(String)
}

nonisolated struct RedisTableValue: Sendable {
    var primaryTitle: String
    var secondaryTitle: String
    var rows: [RedisFieldRow]
}

nonisolated struct RedisKeyInspection: Sendable {
    var key: String
    var type: RedisKeyType
    var ttl: Int64
    var cardinality: Int?
    var memoryBytes: Int?
    var truncated: Bool
    var value: RedisDecodedValue

    var ttlText: String {
        if ttl == -1 { return "永不过期" }
        if ttl == -2 { return "已不存在" }
        return Self.formatDuration(ttl)
    }

    var cardinalityText: String {
        guard let cardinality else { return "—" }
        return cardinality.formatted()
    }

    var memoryText: String {
        guard let memoryBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds < 3_600 { return "\(seconds / 60) 分 \(seconds % 60) 秒" }
        if seconds < 86_400 { return "\(seconds / 3_600) 小时" }
        return "\(seconds / 86_400) 天"
    }
}
