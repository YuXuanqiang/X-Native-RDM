import Foundation

nonisolated enum RedisCommand {
    static func hello(username: String, password: String) -> [Data] {
        var arguments = [utf8("HELLO"), utf8("3")]
        if !password.isEmpty {
            arguments.append(utf8("AUTH"))
            arguments.append(utf8(username.isEmpty ? "default" : username))
            arguments.append(utf8(password))
        }
        arguments.append(utf8("SETNAME"))
        arguments.append(utf8("XNativeRDM"))
        return arguments
    }

    static func auth(username: String, password: String) -> [Data] {
        if username.isEmpty {
            [utf8("AUTH"), utf8(password)]
        } else {
            [utf8("AUTH"), utf8(username), utf8(password)]
        }
    }

    static func select(_ database: Int) -> [Data] {
        [utf8("SELECT"), utf8(String(database))]
    }

    static func configGet(_ parameter: String) -> [Data] {
        [utf8("CONFIG"), utf8("GET"), utf8(parameter)]
    }

    static func ping() -> [Data] {
        [utf8("PING")]
    }

    static func info(_ section: String? = nil) -> [Data] {
        if let section, !section.isEmpty {
            [utf8("INFO"), utf8(section)]
        } else {
            [utf8("INFO")]
        }
    }

    static func scan(cursor: String, pattern: String, count: Int) -> [Data] {
        [utf8("SCAN"), utf8(cursor), utf8("MATCH"), utf8(pattern), utf8("COUNT"), utf8(String(count))]
    }

    static func type(_ key: String) -> [Data] {
        [utf8("TYPE"), utf8(key)]
    }

    static func ttl(_ key: String) -> [Data] {
        [utf8("TTL"), utf8(key)]
    }

    static func memoryUsage(_ key: String) -> [Data] {
        [utf8("MEMORY"), utf8("USAGE"), utf8(key)]
    }

    static func dbSize() -> [Data] {
        [utf8("DBSIZE")]
    }

    static func strlen(_ key: String) -> [Data] {
        [utf8("STRLEN"), utf8(key)]
    }

    static func get(_ key: String) -> [Data] {
        [utf8("GET"), utf8(key)]
    }

    static func getRange(_ key: String, endInclusive: Int) -> [Data] {
        [utf8("GETRANGE"), utf8(key), utf8("0"), utf8(String(endInclusive))]
    }

    static func set(_ key: String, value: String) -> [Data] {
        [utf8("SET"), utf8(key), utf8(value)]
    }

    static func del(_ key: String) -> [Data] {
        [utf8("DEL"), utf8(key)]
    }

    static func llen(_ key: String) -> [Data] {
        [utf8("LLEN"), utf8(key)]
    }

    static func lrange(_ key: String, stop: Int) -> [Data] {
        [utf8("LRANGE"), utf8(key), utf8("0"), utf8(String(stop))]
    }

    static func scard(_ key: String) -> [Data] {
        [utf8("SCARD"), utf8(key)]
    }

    static func sscan(key: String, cursor: String, count: Int) -> [Data] {
        [utf8("SSCAN"), utf8(key), utf8(cursor), utf8("COUNT"), utf8(String(count))]
    }

    static func hlen(_ key: String) -> [Data] {
        [utf8("HLEN"), utf8(key)]
    }

    static func hscan(key: String, cursor: String, count: Int) -> [Data] {
        [utf8("HSCAN"), utf8(key), utf8(cursor), utf8("COUNT"), utf8(String(count))]
    }

    static func zcard(_ key: String) -> [Data] {
        [utf8("ZCARD"), utf8(key)]
    }

    static func zrangeWithScores(_ key: String, stop: Int) -> [Data] {
        [utf8("ZRANGE"), utf8(key), utf8("0"), utf8(String(stop)), utf8("WITHSCORES")]
    }

    static func xlen(_ key: String) -> [Data] {
        [utf8("XLEN"), utf8(key)]
    }

    static func xrevrange(_ key: String, count: Int) -> [Data] {
        [utf8("XREVRANGE"), utf8(key), utf8("+"), utf8("-"), utf8("COUNT"), utf8(String(count))]
    }

    static func jsonGet(_ key: String) -> [Data] {
        [utf8("JSON.GET"), utf8(key)]
    }

    static func quit() -> [Data] {
        [utf8("QUIT")]
    }

    static func utf8(_ value: String) -> Data {
        Data(value.utf8)
    }
}
