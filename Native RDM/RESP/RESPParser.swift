import Foundation

nonisolated struct RESPParser: Sendable {
    private enum Step {
        case incomplete
        case complete(RESPValue)
    }

    private var buffer = Data()
    private var offset = 0
    var maxPayloadBytes: Int

    init(maxPayloadBytes: Int = 128 * 1024 * 1024) {
        self.maxPayloadBytes = maxPayloadBytes
    }

    mutating func append(_ data: Data) {
        compactIfNeeded()
        buffer.append(data)
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
        offset = 0
    }

    mutating func parseNext() throws -> RESPValue? {
        guard offset < buffer.count else { return nil }
        var cursor = offset
        switch try parseValue(from: &cursor) {
        case .incomplete:
            return nil
        case .complete(let value):
            offset = cursor
            compactIfNeeded()
            return value
        }
    }

    private mutating func compactIfNeeded() {
        guard offset > 0 else { return }
        if offset == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            offset = 0
        } else if offset > 64 * 1024 {
            buffer.removeSubrange(0..<offset)
            offset = 0
        }
    }

    private func parseValue(from cursor: inout Int) throws -> Step {
        guard cursor < buffer.count else { return .incomplete }
        let type = buffer[cursor]
        cursor += 1

        switch type {
        case UInt8(ascii: "+"):
            return try parseLineValue(from: &cursor) { .simpleString(String(decoding: $0, as: UTF8.self)) }
        case UInt8(ascii: "-"):
            return try parseLineValue(from: &cursor) { .error(String(decoding: $0, as: UTF8.self)) }
        case UInt8(ascii: ":"):
            return try parseLineValue(from: &cursor) { .integer(try Self.parseInt64($0)) }
        case UInt8(ascii: "$"):
            return try parseBulk(from: &cursor, asError: false)
        case UInt8(ascii: "*"):
            return try parseAggregate(from: &cursor, make: { .array($0) })
        case UInt8(ascii: "_"):
            return try parseLineValue(from: &cursor) { _ in .null }
        case UInt8(ascii: "#"):
            return try parseLineValue(from: &cursor, transform: Self.parseBoolean)
        case UInt8(ascii: ","):
            return try parseLineValue(from: &cursor, transform: Self.parseDouble)
        case UInt8(ascii: "("):
            return try parseLineValue(from: &cursor) { .bigNumber(String(decoding: $0, as: UTF8.self)) }
        case UInt8(ascii: "!"):
            return try parseBulk(from: &cursor, asError: true)
        case UInt8(ascii: "="):
            return try parseVerbatim(from: &cursor)
        case UInt8(ascii: "%"):
            return try parseMap(from: &cursor)
        case UInt8(ascii: "~"):
            return try parseAggregate(from: &cursor, make: { items in .set(items ?? []) })
        case UInt8(ascii: ">"):
            return try parseAggregate(from: &cursor, make: { items in .push(items ?? []) })
        case UInt8(ascii: "|"):
            switch try parseMap(from: &cursor) {
            case .incomplete:
                return .incomplete
            case .complete:
                return try parseValue(from: &cursor)
            }
        default:
            throw RESPParseError.unexpectedType(type)
        }
    }

    private func parseLineValue(
        from cursor: inout Int,
        transform: (Data) throws -> RESPValue
    ) throws -> Step {
        guard let line = readLine(from: &cursor) else { return .incomplete }
        return .complete(try transform(line))
    }

    private func parseBulk(from cursor: inout Int, asError: Bool) throws -> Step {
        guard let line = readLine(from: &cursor) else { return .incomplete }
        let length = try Self.parseInt64(line)
        if length == -1 {
            return .complete(asError ? .bulkError(Data()) : .bulkString(nil))
        }
        guard length >= 0 else { throw RESPParseError.invalidLength }
        let size = Int(length)
        guard size <= maxPayloadBytes else { throw RESPParseError.payloadTooLarge(size) }
        guard cursor + size + 2 <= buffer.count else { return .incomplete }
        let payload = buffer.subdata(in: cursor..<(cursor + size))
        cursor += size
        try consumeCRLF(from: &cursor)
        return .complete(asError ? .bulkError(payload) : .bulkString(payload))
    }

    private func parseVerbatim(from cursor: inout Int) throws -> Step {
        guard let line = readLine(from: &cursor) else { return .incomplete }
        let length = try Self.parseInt64(line)
        guard length >= 0 else { throw RESPParseError.invalidLength }
        let size = Int(length)
        guard size <= maxPayloadBytes else { throw RESPParseError.payloadTooLarge(size) }
        guard cursor + size + 2 <= buffer.count else { return .incomplete }
        let payload = buffer.subdata(in: cursor..<(cursor + size))
        cursor += size
        try consumeCRLF(from: &cursor)
        guard payload.count >= 4,
              payload[3] == UInt8(ascii: ":")
        else {
            throw RESPParseError.invalidVerbatimString
        }
        let encoding = String(decoding: payload.prefix(3), as: UTF8.self)
        let body = payload.subdata(in: 4..<payload.count)
        return .complete(.verbatimString(encoding: encoding, data: body))
    }

    private func parseAggregate(
        from cursor: inout Int,
        make: ([RESPValue]?) throws -> RESPValue
    ) throws -> Step {
        guard let line = readLine(from: &cursor) else { return .incomplete }
        let count = try Self.parseInt64(line)
        if count == -1 {
            return .complete(try make(nil))
        }
        guard count >= 0 else { throw RESPParseError.invalidLength }
        var items: [RESPValue] = []
        items.reserveCapacity(Int(count))
        for _ in 0..<count {
            switch try parseValue(from: &cursor) {
            case .incomplete:
                return .incomplete
            case .complete(let value):
                items.append(value)
            }
        }
        return .complete(try make(items))
    }

    private func parseMap(from cursor: inout Int) throws -> Step {
        guard let line = readLine(from: &cursor) else { return .incomplete }
        let count = try Self.parseInt64(line)
        guard count >= 0 else { throw RESPParseError.invalidLength }
        var entries: [RESPMapEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0..<count {
            let key: RESPValue
            switch try parseValue(from: &cursor) {
            case .incomplete:
                return .incomplete
            case .complete(let value):
                key = value
            }
            let value: RESPValue
            switch try parseValue(from: &cursor) {
            case .incomplete:
                return .incomplete
            case .complete(let parsed):
                value = parsed
            }
            entries.append(RESPMapEntry(key: key, value: value))
        }
        return .complete(.map(entries))
    }

    private func readLine(from cursor: inout Int) -> Data? {
        var index = cursor
        while index + 1 < buffer.count {
            if buffer[index] == 0x0D && buffer[index + 1] == 0x0A {
                let line = buffer.subdata(in: cursor..<index)
                cursor = index + 2
                return line
            }
            index += 1
        }
        return nil
    }

    private func consumeCRLF(from cursor: inout Int) throws {
        guard cursor + 1 < buffer.count else { throw RESPParseError.missingCRLF }
        guard buffer[cursor] == 0x0D, buffer[cursor + 1] == 0x0A else {
            throw RESPParseError.missingCRLF
        }
        cursor += 2
    }

    private static func parseInt64(_ data: Data) throws -> Int64 {
        let text = String(decoding: data, as: UTF8.self)
        guard let value = Int64(text) else { throw RESPParseError.invalidInteger }
        return value
    }

    private static func parseBoolean(_ data: Data) throws -> RESPValue {
        switch String(decoding: data, as: UTF8.self) {
        case "t":
            return .boolean(true)
        case "f":
            return .boolean(false)
        default:
            throw RESPParseError.invalidBoolean
        }
    }

    private static func parseDouble(_ data: Data) throws -> RESPValue {
        let text = String(decoding: data, as: UTF8.self)
        switch text {
        case "inf":
            return .double(.infinity)
        case "-inf":
            return .double(-.infinity)
        case "nan":
            return .double(.nan)
        default:
            guard let value = Double(text) else { throw RESPParseError.invalidDouble }
            return .double(value)
        }
    }
}
