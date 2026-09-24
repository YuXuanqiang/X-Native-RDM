import Foundation

nonisolated enum RedisClientError: Error, LocalizedError, Sendable, Equatable {
    case invalidHost
    case invalidPort
    case notConnected
    case disconnected
    case connectTimeout
    case commandTimeout
    case cancelled
    case server(String)
    case protocolViolation(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "主机地址无效"
        case .invalidPort:
            return "端口无效"
        case .notConnected:
            return "尚未连接到 Redis"
        case .disconnected:
            return "连接已断开"
        case .connectTimeout:
            return "连接超时"
        case .commandTimeout:
            return "命令执行超时"
        case .cancelled:
            return "连接已取消"
        case .server(let message):
            return message
        case .protocolViolation(let message):
            return "协议错误：\(message)"
        }
    }

    static func isUnknownCommand(_ message: String) -> Bool {
        message.lowercased().contains("unknown command")
    }
}
