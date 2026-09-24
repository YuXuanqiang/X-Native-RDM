import Foundation

nonisolated enum RESPEncoder {
    private static let crlf = Data([0x0D, 0x0A])

    static func encodeCommand(_ arguments: [Data]) -> Data {
        var data = Data()
        appendLine("*\(arguments.count)", to: &data)
        for argument in arguments {
            appendBulk(argument, to: &data)
        }
        return data
    }

    static func encodeCommand(_ arguments: [String]) -> Data {
        encodeCommand(arguments.map { Data($0.utf8) })
    }

    static func encode(_ value: RESPValue) -> Data {
        var data = Data()
        write(value, to: &data)
        return data
    }

    private static func write(_ value: RESPValue, to data: inout Data) {
        switch value {
        case .simpleString(let text):
            appendLine("+\(text)", to: &data)
        case .error(let message):
            appendLine("-\(message)", to: &data)
        case .integer(let number):
            appendLine(":\(number)", to: &data)
        case .bulkString(let payload):
            appendBulk(payload, to: &data)
        case .array(let items):
            guard let items else {
                appendLine("*-1", to: &data)
                return
            }
            appendLine("*\(items.count)", to: &data)
            for item in items {
                write(item, to: &data)
            }
        case .null:
            appendLine("_", to: &data)
        case .boolean(let flag):
            appendLine(flag ? "#t" : "#f", to: &data)
        case .double(let number):
            appendLine(",\(formatDouble(number))", to: &data)
        case .bigNumber(let number):
            appendLine("(\(number)", to: &data)
        case .bulkError(let payload):
            appendLine("!\(payload.count)", to: &data)
            data.append(payload)
            data.append(crlf)
        case .verbatimString(let encoding, let payload):
            let header = Data(encoding.utf8) + Data([UInt8(ascii: ":")]) + payload
            appendLine("=\(header.count)", to: &data)
            data.append(header)
            data.append(crlf)
        case .map(let entries):
            appendLine("%\(entries.count)", to: &data)
            for entry in entries {
                write(entry.key, to: &data)
                write(entry.value, to: &data)
            }
        case .set(let items):
            appendLine("~\(items.count)", to: &data)
            for item in items {
                write(item, to: &data)
            }
        case .push(let items):
            appendLine(">\(items.count)", to: &data)
            for item in items {
                write(item, to: &data)
            }
        }
    }

    private static func appendBulk(_ payload: Data?, to data: inout Data) {
        guard let payload else {
            appendLine("$-1", to: &data)
            return
        }
        appendLine("$\(payload.count)", to: &data)
        data.append(payload)
        data.append(crlf)
    }

    private static func appendLine(_ line: String, to data: inout Data) {
        data.append(Data(line.utf8))
        data.append(crlf)
    }

    private static func formatDouble(_ value: Double) -> String {
        if value.isNaN { return "nan" }
        if value == .infinity { return "inf" }
        if value == -.infinity { return "-inf" }
        return String(value)
    }
}
