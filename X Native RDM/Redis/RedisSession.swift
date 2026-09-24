import Foundation

@Observable
final class RedisSession {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var status: Status = .disconnected
    private(set) var handshake: RedisHandshake?
    private(set) var lastResponse = ""
    private(set) var lastLatency: Duration?
    let browser = RedisKeyBrowser()

    private var client: RedisClient?
    private var connectTask: Task<Void, Never>?
    private var generation = 0

    var isConnected: Bool {
        if case .connected = status { true } else { false }
    }

    func connect(profile: ConnectionProfile, password: String) {
        disconnect()
        generation += 1
        let generation = self.generation
        status = .connecting
        lastResponse = ""
        lastLatency = nil
        handshake = nil

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
                await reloadKeys()
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
        status = .disconnected
        browser.reset()
        Task {
            await client?.disconnect()
        }
    }

    func reloadKeys() async {
        let generation = self.generation
        guard let client else { return }
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
}
