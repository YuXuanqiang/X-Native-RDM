import Foundation
import Network
import Security

nonisolated private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        body()
    }
}

actor RedisClient {
    var isConnected: Bool { connection != nil }

    private let nwQueue = DispatchQueue(label: "com.yion.XNativeRDM.redis.nw")
    private var connection: NWConnection?
    private var parser = RESPParser()
    private var waiters: [CheckedContinuation<RESPValue, Error>] = []
    private var receiving = false

    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: Int,
        useTLS: Bool,
        verifyTLSCertificate: Bool,
        timeout: Duration
    ) async throws -> RedisHandshake {
        try await disconnect(sendQuit: false)

        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RedisClientError.invalidHost
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)), (1...65535).contains(port) else {
            throw RedisClientError.invalidPort
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host.trimmingCharacters(in: .whitespacesAndNewlines)),
            port: nwPort,
            using: Self.parameters(
                useTLS: useTLS,
                verifyTLSCertificate: verifyTLSCertificate,
                timeout: timeout,
                queue: nwQueue
            )
        )
        self.connection = connection

        do {
            try await waitUntilReady(connection, timeout: timeout)
            startReceiveLoop()
            let handshake = try await authenticate(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                database: database,
                timeout: timeout
            )
            _ = try await execute(RedisCommand.ping(), timeout: timeout)
            return handshake
        } catch {
            await disconnect(sendQuit: false)
            throw error
        }
    }

    func execute(_ arguments: [Data], timeout: Duration = .seconds(15)) async throws -> RESPValue {
        guard connection != nil else { throw RedisClientError.notConnected }

        do {
            return try await withThrowingTaskGroup(of: RESPValue.self) { group in
                group.addTask {
                    try await self.sendAndWait(arguments)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw RedisClientError.commandTimeout
                }
                let value = try await group.next()!
                group.cancelAll()
                return value
            }
        } catch {
            if error as? RedisClientError == .commandTimeout {
                await disconnect(sendQuit: false)
            }
            throw error
        }
    }

    func execute(_ arguments: [String], timeout: Duration = .seconds(15)) async throws -> RESPValue {
        try await execute(arguments.map(RedisCommand.utf8), timeout: timeout)
    }

    func disconnect(sendQuit: Bool = true) async {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(throwing: RedisClientError.cancelled) }

        if sendQuit, connection != nil {
            try? await send(RESPEncoder.encodeCommand(RedisCommand.quit()))
        }

        connection?.cancel()
        connection = nil
        parser.reset()
        receiving = false
    }

    private func authenticate(username: String, password: String, database: Int, timeout: Duration) async throws -> RedisHandshake {
        do {
            let reply = try await execute(RedisCommand.hello(username: username, password: password), timeout: timeout)
            try await selectIfNeeded(database, timeout: timeout)
            return reply.handshakeInfo()
        } catch RedisClientError.server(let message) where RedisClientError.isUnknownCommand(message) {
            try await legacyAuth(username: username, password: password, timeout: timeout)
            try await selectIfNeeded(database, timeout: timeout)
            return RedisHandshake(protocolVersion: 2, server: "Redis", version: nil, mode: nil, role: nil)
        }
    }

    private func legacyAuth(username: String, password: String, timeout: Duration) async throws {
        guard !password.isEmpty else { return }
        _ = try await execute(RedisCommand.auth(username: username, password: password), timeout: timeout)
    }

    private func selectIfNeeded(_ database: Int, timeout: Duration) async throws {
        guard database != 0 else { return }
        _ = try await execute(RedisCommand.select(database), timeout: timeout)
    }

    private func sendAndWait(_ arguments: [Data]) async throws -> RESPValue {
        try Task.checkCancellation()
        try await send(RESPEncoder.encodeCommand(arguments))
        let value = try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
        if let message = value.errorMessage {
            throw RedisClientError.server(message)
        }
        return value
    }

    private func send(_ data: Data) async throws {
        guard let connection else { throw RedisClientError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func waitUntilReady(_ connection: NWConnection, timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.observeReady(connection)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw RedisClientError.connectTimeout
            }
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                connection.cancel()
                group.cancelAll()
                throw error
            }
        }
    }

    private func observeReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = { newState in
                        Task { await self.handleStateChange(newState) }
                    }
                    gate.resume { continuation.resume() }
                case .failed(let error):
                    gate.resume { continuation.resume(throwing: error) }
                case .cancelled:
                    gate.resume { continuation.resume(throwing: RedisClientError.cancelled) }
                default:
                    break
                }
            }
            connection.start(queue: nwQueue)
        }
    }

    private func handleStateChange(_ state: NWConnection.State) async {
        switch state {
        case .failed(let error):
            failAll(error)
            connection = nil
        case .cancelled:
            failAll(RedisClientError.disconnected)
            connection = nil
        default:
            break
        }
    }

    private func startReceiveLoop() {
        guard !receiving else { return }
        receiving = true
        Task { await self.receiveLoop() }
    }

    private func receiveLoop() async {
        defer { receiving = false }
        while connection != nil, !Task.isCancelled {
            do {
                let chunk = try await receiveChunk()
                guard !chunk.isEmpty else { continue }
                parser.append(chunk)
                while let value = try parser.parseNext() {
                    deliver(value)
                }
            } catch {
                failAll(error)
                connection?.cancel()
                connection = nil
                break
            }
        }
    }

    private func receiveChunk() async throws -> Data {
        guard let connection else { throw RedisClientError.disconnected }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: RedisClientError.disconnected)
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }

    private func deliver(_ value: RESPValue) {
        if case .push = value {
            return
        }
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume(returning: value)
    }

    private func failAll(_ error: Error) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(throwing: error) }
    }

    private static func parameters(
        useTLS: Bool,
        verifyTLSCertificate: Bool,
        timeout: Duration,
        queue: DispatchQueue
    ) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = max(1, Int(timeout.components.seconds))

        if useTLS {
            let tls = NWProtocolTLS.Options()
            if !verifyTLSCertificate {
                sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, completion in
                    completion(true)
                }, queue)
            }
            return NWParameters(tls: tls, tcp: tcp)
        }
        return NWParameters(tls: nil, tcp: tcp)
    }
}
