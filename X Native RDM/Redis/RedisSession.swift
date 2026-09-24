import Foundation

@Observable
final class RedisSession {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    struct DatabaseOption: Identifiable, Equatable {
        var id: Int { index }
        var index: Int
        var keyCount: Int?
    }

    private(set) var status: Status = .disconnected
    private(set) var handshake: RedisHandshake?
    private(set) var lastResponse = ""
    private(set) var lastLatency: Duration?
    private(set) var activeDatabase: Int?
    private(set) var databaseOptions: [DatabaseOption] = []
    private(set) var isLoadingDatabases = false
    let browser = RedisKeyBrowser()

    private var client: RedisClient?
    private var connectTask: Task<Void, Never>?
    private var generation = 0

    var isConnected: Bool {
        if case .connected = status { true } else { false }
    }

    var needsDatabaseSelection: Bool {
        isConnected && activeDatabase == nil
    }

    func connect(profile: ConnectionProfile, password: String) {
        disconnect()
        generation += 1
        let generation = self.generation
        status = .connecting
        lastResponse = ""
        lastLatency = nil
        handshake = nil
        activeDatabase = nil
        databaseOptions = []

        let client = RedisClient()
        self.client = client
        let timeout = Duration.seconds(max(1, profile.connectTimeout))

        connectTask = Task {
            do {
                let result = try await client.connect(
                    host: profile.host,
                    port: profile.port,
                    username: profile.username,
                    password: password,
                    database: profile.database,
                    useTLS: profile.useTLS,
                    verifyTLSCertificate: profile.verifyTLSCertificate,
                    timeout: timeout
                )
                try Task.checkCancellation()
                guard generation == self.generation else { return }
                handshake = result
                status = .connected
                lastResponse = result.summary
                activeDatabase = profile.database
                if profile.database != nil {
                    await reloadKeys()
                } else {
                    await refreshDatabaseOptions()
                }
            } catch is CancellationError {
                guard generation == self.generation else { return }
                status = .disconnected
            } catch {
                guard generation == self.generation else { return }
                status = .failed(error.localizedDescription)
                self.client = nil
            }
        }
    }

    func disconnect() {
        generation += 1
        connectTask?.cancel()
        connectTask = nil
        let client = self.client
        self.client = nil
        handshake = nil
        lastLatency = nil
        activeDatabase = nil
        databaseOptions = []
        isLoadingDatabases = false
        status = .disconnected
        browser.reset()
        Task {
            await client?.disconnect()
        }
    }

    func selectDatabase(_ database: Int) async {
        let generation = self.generation
        guard let client else { return }
        do {
            _ = try await client.execute(RedisCommand.select(database))
            guard generation == self.generation else { return }
            activeDatabase = database
            await reloadKeys()
        } catch {
            guard generation == self.generation else { return }
            lastResponse = error.localizedDescription
            handleClientError(error)
        }
    }

    func refreshDatabaseOptions() async {
        let generation = self.generation
        guard let client else { return }
        isLoadingDatabases = true
        defer {
            if generation == self.generation {
                isLoadingDatabases = false
            }
        }

        do {
            let count = try await Self.readDatabaseCount(using: client)
            let keyCounts = try await Self.readKeyspaceCounts(using: client)
            guard generation == self.generation else { return }
            databaseOptions = (0..<count).map { index in
                DatabaseOption(index: index, keyCount: keyCounts[index])
            }
        } catch {
            guard generation == self.generation else { return }
            if databaseOptions.isEmpty {
                databaseOptions = (0..<16).map { DatabaseOption(index: $0, keyCount: nil) }
            }
            if shouldDropConnection(error) {
                handleClientError(error)
            }
        }
    }

    func reloadKeys() async {
        let generation = self.generation
        guard let client, activeDatabase != nil else { return }
        do {
            try await browser.reload(using: client)
        } catch {
            guard generation == self.generation else { return }
            handleClientError(error)
        }
    }

    func inspectKey(_ key: String) async {
        let generation = self.generation
        guard let client else { return }
        do {
            try await browser.inspect(using: client, key: key)
        } catch {
            guard generation == self.generation else { return }
            handleClientError(error)
        }
    }

    func saveStringValue() async {
        let generation = self.generation
        guard let client else { return }
        do {
            try await browser.saveString(using: client)
        } catch {
            guard generation == self.generation else { return }
            browser.errorMessage = error.localizedDescription
            handleClientError(error)
        }
    }

    func deleteKey(_ key: String) async {
        let generation = self.generation
        guard let client else { return }
        do {
            try await browser.deleteKey(using: client, key: key)
        } catch {
            guard generation == self.generation else { return }
            browser.errorMessage = error.localizedDescription
            handleClientError(error)
        }
    }

    func run(_ command: [String]) async {
        let generation = self.generation
        guard let client else {
            lastResponse = RedisClientError.notConnected.localizedDescription ?? "尚未连接到 Redis"
            return
        }
        guard !command.isEmpty else {
            lastResponse = "请输入命令"
            return
        }

        let started = ContinuousClock().now
        do {
            let value = try await client.execute(command)
            guard generation == self.generation else { return }
            lastLatency = ContinuousClock().now - started
            lastResponse = value.displayText
        } catch {
            guard generation == self.generation else { return }
            lastLatency = ContinuousClock().now - started
            lastResponse = error.localizedDescription
            handleClientError(error)
        }
    }

    private func handleClientError(_ error: Error) {
        if shouldDropConnection(error) {
            status = .failed(error.localizedDescription)
            client = nil
            activeDatabase = nil
            databaseOptions = []
            browser.reset()
        }
    }

    private func shouldDropConnection(_ error: Error) -> Bool {
        switch error as? RedisClientError {
        case .disconnected, .cancelled, .notConnected, .commandTimeout, .connectTimeout:
            true
        default:
            false
        }
    }

    private static func readDatabaseCount(using client: RedisClient) async throws -> Int {
        do {
            let reply = try await client.execute(RedisCommand.configGet("databases"))
            let elements = reply.elements
            if elements.count >= 2, let value = elements[1].stringContent, let count = Int(value), count > 0 {
                return min(count, 256)
            }
            if let mapValue = reply.mapValue(for: "databases"),
               let value = mapValue.stringContent,
               let count = Int(value),
               count > 0 {
                return min(count, 256)
            }
        } catch RedisClientError.server {
            // CONFIG may be disabled; fall through to default.
        }
        return 16
    }

    private static func readKeyspaceCounts(using client: RedisClient) async throws -> [Int: Int] {
        let reply = try await client.execute(RedisCommand.info("keyspace"))
        guard let text = reply.stringContent else { return [:] }
        var result: [Int: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("db"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let indexText = trimmed[trimmed.index(after: trimmed.startIndex)..<colon]
            guard let index = Int(indexText) else { continue }
            let details = trimmed[trimmed.index(after: colon)...]
            if let keysRange = details.range(of: "keys="),
               let countText = details[keysRange.upperBound...]
                .prefix(while: { $0.isNumber })
                .nilIfEmpty,
               let count = Int(countText) {
                result[index] = count
            }
        }
        return result
    }
}

private extension RESPValue {
    func mapValue(for key: String) -> RESPValue? {
        let needle = key.lowercased()
        if case .map(let entries) = self {
            return entries.first { $0.key.stringContent?.lowercased() == needle }?.value
        }
        let items = elements
        var index = 0
        while index + 1 < items.count {
            if items[index].stringContent?.lowercased() == needle {
                return items[index + 1]
            }
            index += 2
        }
        return nil
    }
}

private extension Substring {
    var nilIfEmpty: Substring? {
        isEmpty ? nil : self
    }
}
