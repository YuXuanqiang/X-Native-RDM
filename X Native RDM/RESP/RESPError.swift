import Foundation

nonisolated enum RESPParseError: Error, LocalizedError, Sendable, Equatable {
    case unexpectedType(UInt8)
    case invalidInteger
    case invalidLength
    case missingCRLF
    case payloadTooLarge(Int)
    case invalidBoolean
    case invalidDouble
    case invalidVerbatimString

    var errorDescription: String? {
        switch self {
        case .unexpectedType(let byte):
            return "无法识别的 RESP 类型：0x\(String(byte, radix: 16))"
        case .invalidInteger:
            return "RESP 整数格式无效"
        case .invalidLength:
            return "RESP 长度无效"
        case .missingCRLF:
            return "RESP 缺少 CRLF 终止符"
        case .payloadTooLarge(let size):
            return "RESP 载荷过大（\(size) 字节）"
        case .invalidBoolean:
            return "RESP 布尔值无效"
        case .invalidDouble:
            return "RESP 浮点数无效"
        case .invalidVerbatimString:
            return "RESP verbatim 字符串无效"
        }
    }
}
