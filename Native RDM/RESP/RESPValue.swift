import Foundation

nonisolated struct RESPMapEntry: Sendable, Hashable {
    var key: RESPValue
    var value: RESPValue
}

nonisolated enum RESPValue: Sendable, Hashable {
    case simpleString(String)
    case error(String)
    case integer(Int64)
    case bulkString(Data?)
    case array([RESPValue]?)
    case null
    case boolean(Bool)
    case double(Double)
    case bigNumber(String)
    case bulkError(Data)
    case verbatimString(encoding: String, data: Data)
    case map([RESPMapEntry])
    case set([RESPValue])
    case push([RESPValue])
}

extension RESPValue {
    var errorMessage: String? {
        switch self {
        case .error(let message):
            return message
        case .bulkError(let data):
            return String(data: data, encoding: .utf8) ?? data.hexPreview
        default:
            return nil
        }
    }

    var stringContent: String? {
        switch self {
        case .simpleString(let value), .error(let value), .bigNumber(let value):
            return value
        case .integer(let value):
            return String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .double(let value):
            return String(value)
        case .bulkString(let data):
            return data.flatMap { String(data: $0, encoding: .utf8) }
        case .bulkError(let data):
            return String(data: data, encoding: .utf8)
        case .verbatimString(_, let data):
            return String(data: data, encoding: .utf8)
        case .null:
            return nil
        default:
            return nil
        }
    }

    var integerValue: Int64? {
        switch self {
        case .integer(let value):
            return value
        default:
            return stringContent.flatMap(Int64.init)
        }
    }

    var elements: [RESPValue] {
        switch self {
        case .array(let items?):
            return items
        case .set(let items), .push(let items):
            return items
        default:
            return []
        }
    }

    var bulkData: Data? {
        switch self {
        case .bulkString(let data):
            return data
        case .verbatimString(_, let data), .bulkError(let data):
            return data
        default:
            return nil
        }
    }

    var lossyString: String {
        if let text = stringContent { return text }
        if let data = bulkData {
            return data.hexPreview
        }
        return displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayText: String {
        format(indent: 0)
    }

    fileprivate func format(indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .simpleString(let value):
            return "\(pad)\(value)"
        case .error(let message):
            return "\(pad)(error) \(message)"
        case .integer(let value):
            return "\(pad)\(value)"
        case .bulkString(let data):
            guard let data else { return "\(pad)(nil)" }
            if let text = String(data: data, encoding: .utf8), text.isValidDisplayString {
                return "\(pad)\(text)"
            }
            return "\(pad)(binary \(data.count) bytes) \(data.hexPreview)"
        case .array(let items):
            guard let items else { return "\(pad)(nil array)" }
            if items.isEmpty { return "\(pad)[]" }
            var lines = ["\(pad)["]
            for item in items {
                lines.append(item.format(indent: indent + 1))
            }
            lines.append("\(pad)]")
            return lines.joined(separator: "\n")
        case .null:
            return "\(pad)(null)"
        case .boolean(let value):
            return "\(pad)\(value)"
        case .double(let value):
            return "\(pad)\(value)"
        case .bigNumber(let value):
            return "\(pad)\(value)"
        case .bulkError(let data):
            let message = String(data: data, encoding: .utf8) ?? data.hexPreview
            return "\(pad)(error) \(message)"
        case .verbatimString(let encoding, let data):
            let body = String(data: data, encoding: .utf8) ?? data.hexPreview
            return "\(pad)\(encoding):\(body)"
        case .map(let entries):
            if entries.isEmpty { return "\(pad){}" }
            var lines = ["\(pad){"]
            for entry in entries {
                lines.append("\(pad)  \(entry.key.format(indent: 0).trimmingCharacters(in: .whitespaces)):")
                lines.append(entry.value.format(indent: indent + 2))
            }
            lines.append("\(pad)}")
            return lines.joined(separator: "\n")
        case .set(let items):
            return RESPValue.array(items).format(indent: indent)
        case .push(let items):
            return "\(pad)(push)\n\(RESPValue.array(items).format(indent: indent))"
        }
    }
}

extension Data {
    var hexPreview: String {
        prefix(24).map { String(format: "%02x", $0) }.joined(separator: " ")
            + (count > 24 ? " …" : "")
    }
}

private extension String {
    var isValidDisplayString: Bool {
        !contains(where: { $0.isASCII && ($0.asciiValue! < 32 && $0 != "\t" && $0 != "\n" && $0 != "\r") })
    }
}
