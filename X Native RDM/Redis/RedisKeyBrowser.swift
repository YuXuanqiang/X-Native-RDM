import Foundation

@Observable
final class RedisKeyBrowser {
    var pattern = "*"
    var separator = ":"
    var selectedNodeID: String?
    var isScanning = false
    var isInspecting = false
    var truncated = false
    var scanProgress = 0
    var dbSize: Int?
    var errorMessage: String?
    var roots: [KeyOutlineNode] = []
    var inspection: RedisKeyInspection?
    var editedString = ""
    var originalString = ""

    private var scannedKeys: [String] = []
    private var scanGeneration = 0
    private var inspectGeneration = 0

    static let maxKeys = 8_000
    static let collectionPage = 200
    static let stringPreviewBytes = 512 * 1024

    var selectedRedisKey: String? {
        guard let selectedNodeID else { return nil }
        return redisKey(in: roots, id: selectedNodeID)
    }

    var canSaveString: Bool {
        guard case .string(_, let binary) = inspection?.value else { return false }
        return !binary && inspection?.truncated == false && editedString != originalString
    }

    func reset() {
        scanGeneration += 1
        inspectGeneration += 1
        pattern = "*"
        selectedNodeID = nil
        isScanning = false
        isInspecting = false
        truncated = false
        scanProgress = 0
        dbSize = nil
        errorMessage = nil
        roots = []
        scannedKeys = []
        inspection = nil
        editedString = ""
        originalString = ""
    }

    func rebuildTree() {
        roots = KeyTreeBuilder.build(keys: scannedKeys, separator: separator)
    }

    func reload(using client: RedisClient) async throws {
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        errorMessage = nil
        truncated = false
        scanProgress = 0
        inspection = nil
        selectedNodeID = nil
        editedString = ""
        originalString = ""
        defer {
            if generation == scanGeneration {
                isScanning = false
            }
        }

        do {
            dbSize = try await Self.readDBSize(client)
            let match = Self.normalizedPattern(pattern)
            var cursor = "0"
            var keys: [String] = []
            var seen = Set<String>()

            repeat {
                try Task.checkCancellation()
                guard generation == scanGeneration else { return }
                let page = try await Self.scanPage(client, cursor: cursor, pattern: match)
                for key in page.keys where seen.insert(key).inserted {
                    keys.append(key)
                }
                cursor = page.cursor
                scanProgress = keys.count
                if keys.count >= Self.maxKeys {
                    truncated = true
                    break
                }
            } while cursor != "0"

            guard generation == scanGeneration else { return }
            scannedKeys = keys
            rebuildTree()
        } catch is CancellationError {
            return
        } catch {
            guard generation == scanGeneration else { return }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func inspect(using client: RedisClient, key: String) async throws {
        inspectGeneration += 1
        let generation = inspectGeneration
        isInspecting = true
        errorMessage = nil
        defer {
            if generation == inspectGeneration {
                isInspecting = false
            }
        }

        do {
            let snapshot = try await Self.loadInspection(client, key: key)
            guard generation == inspectGeneration else { return }
            inspection = snapshot
            if case .string(let text, _) = snapshot.value {
                editedString = text
                originalString = text
            } else {
                editedString = ""
                originalString = ""
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == inspectGeneration else { return }
            inspection = nil
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func saveString(using client: RedisClient) async throws {
        guard let key = inspection?.key else { return }
        _ = try await client.execute(RedisCommand.set(key, value: editedString))
        originalString = editedString
        try await inspect(using: client, key: key)
    }

    func deleteKey(using client: RedisClient, key: String) async throws {
        _ = try await client.execute(RedisCommand.del(key))
        scannedKeys.removeAll { $0 == key }
        rebuildTree()
        if selectedRedisKey == key {
            selectedNodeID = nil
            inspection = nil
        }
        dbSize = try? await Self.readDBSize(client)
    }

    private func redisKey(in nodes: [KeyOutlineNode], id: String) -> String? {
        for node in nodes {
            if node.id == id {
                return node.redisKey
            }
            if let children = node.children, let match = redisKey(in: children, id: id) {
                return match
            }
        }
        return nil
    }

    static func normalizedPattern(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "*" }
        if trimmed.contains("*") || trimmed.contains("?") || trimmed.contains("[") {
            return trimmed
        }
        return "*\(trimmed)*"
    }

    private static func readDBSize(_ client: RedisClient) async throws -> Int? {
        do {
            return try await client.execute(RedisCommand.dbSize()).integerValue.map(Int.init)
        } catch RedisClientError.server {
            return nil
        }
    }

    private static func scanPage(_ client: RedisClient, cursor: String, pattern: String) async throws -> (cursor: String, keys: [String]) {
        let reply = try await client.execute(RedisCommand.scan(cursor: cursor, pattern: pattern, count: 1_000), timeout: .seconds(30))
        let items = reply.elements
        guard items.count >= 2 else {
            throw RedisClientError.protocolViolation("SCAN 响应格式无效")
        }
        let next = items[0].stringContent ?? "0"
        let keys = items[1].elements.map(\.lossyString)
        return (next, keys)
    }

    private static func loadInspection(_ client: RedisClient, key: String) async throws -> RedisKeyInspection {
        let typeRaw = try await client.execute(RedisCommand.type(key)).stringContent ?? "none"
        let kind = RedisKeyType(serverType: typeRaw)
        let ttl = try await client.execute(RedisCommand.ttl(key)).integerValue ?? -2
        let memory = try? await client.execute(RedisCommand.memoryUsage(key)).integerValue.map(Int.init)

        if kind == .none || ttl == -2 {
            return RedisKeyInspection(
                key: key,
                type: .none,
                ttl: ttl,
                cardinality: 0,
                memoryBytes: memory,
                truncated: false,
                value: .empty
            )
        }

        let loaded = try await loadValue(client, key: key, type: kind)
        return RedisKeyInspection(
            key: key,
            type: kind,
            ttl: ttl,
            cardinality: loaded.cardinality,
            memoryBytes: memory,
            truncated: loaded.truncated,
            value: loaded.value
        )
    }

    private static func loadValue(
        _ client: RedisClient,
        key: String,
        type: RedisKeyType
    ) async throws -> (value: RedisDecodedValue, cardinality: Int?, truncated: Bool) {
        switch type {
        case .string:
            return try await loadString(client, key: key)
        case .list:
            return try await loadList(client, key: key)
        case .set:
            return try await loadSet(client, key: key)
        case .zset:
            return try await loadZSet(client, key: key)
        case .hash:
            return try await loadHash(client, key: key)
        case .stream:
            return try await loadStream(client, key: key)
        case .json:
            return try await loadJSON(client, key: key)
        case .none:
            return (.empty, 0, false)
        case .other(let raw):
            return (.raw("暂不支持的类型：\(raw)"), nil, false)
        }
    }

    private static func loadString(_ client: RedisClient, key: String) async throws -> (RedisDecodedValue, Int?, Bool) {
        let length = try await client.execute(RedisCommand.strlen(key)).integerValue.map(Int.init) ?? 0
        let truncated = length > stringPreviewBytes
        let reply = truncated
            ? try await client.execute(RedisCommand.getRange(key, endInclusive: stringPreviewBytes - 1))
            : try await client.execute(RedisCommand.get(key))
        if let data = reply.bulkData, String(data: data, encoding: .utf8) == nil {
            return (.string(text: data.hexPreview, binary: true), length, truncated)
        }
        return (.string(text: reply.stringContent ?? "", binary: false), length, truncated)
    }

    private static func loadList(_ client: RedisClient, key: String) async throws -> (RedisDecodedValue, Int?, Bool) {
        let total = try await client.execute(RedisCommand.llen(key)).integerValue.map(Int.init) ?? 0
        let items = try await client.execute(RedisCommand.lrange(key, stop: collectionPage - 1)).elements
        let rows = items.enumerated().map { RedisFieldRow(id: $0.offset, primary: String($0.offset), secondary: $0.element.lossyString) }
        return (.table(RedisTableValue(primaryTitle: "索引", secondaryTitle: "值", rows: rows)), total, total > rows.count)
    }

    private static func loadSet(_ client: RedisClient, key: String) async throws -> (RedisDecodedValue, Int?, Bool) {
        let total = try await client.execute(RedisCommand.scard(key)).integerValue.map(Int.init) ?? 0
        var cursor = "0"
        var members: [String] = []
        repeat {
            let reply = try await client.execute(RedisCommand.sscan(key: key, cursor: cursor, count: collectionPage)).elements
            guard reply.count >= 2 else { break }
            cursor = reply[0].stringContent ?? "0"
            members.append(contentsOf: reply[1].elements.map(\.lossyString))
            if members.count >= collectionPage { break }
        } while cursor != "0"
        if members.count > collectionPage {
            members = Array(members.prefix(collectionPage))
        }
        let rows = members.enumerated().map { RedisFieldRow(id: $0.offset, primary: String($0.offset + 1), secondary: $0.element) }
        return (.table(RedisTableValue(primaryTitle: "#", secondaryTitle: "成员", rows: rows)), total, total > rows.count)
    }

    private static func loadZSet(_ client: RedisClient, key: String) async throws -> (RedisDecodedValue, Int?, Bool) {
        let total = try await client.execute(RedisCommand.zcard(key)).integerValue.map(Int.init) ?? 0
        let items = try await client.execute(RedisCommand.zrangeWithScores(key, stop: collectionPage - 1)).elements
        var rows: [RedisFieldRow] = []
        var index = 0
        var i = 0
        while i + 1 < items.count {
            rows.append(RedisFieldRow(id: index, primary: items[i + 1].lossyString, secondary: items[i].lossyString))
            index += 1
            i += 2
        }
        return (.table(RedisTableValue(primaryTitle: "分数", secondaryTitle: "成员", rows: rows)), total, total > rows.count)
    }

    private static func loadHash(_ client: RedisClient, key: String) async throws -> (RedisDecodedValue, Int?, Bool) {
        let total = try await client.execute(RedisCommand.hlen(key)).integerValue.map(Int.init) ?? 0
        var cursor = "0"
        var pairs: [(String, String)] = []
        repeat {
            let reply = try await client.execute(RedisCommand.hscan(key: key, cursor: cursor, count: collectionPage)).elements
            guard reply.count >= 2 else { break }
            cursor = reply[0].stringContent ?? "0"
            let elements = reply[1].elements
            var i = 0
            while i + 1 < elements.count {
                pairs.append((elements[i].lossyString, elements[i + 1].lossyString))
                i += 2
            }
            if pairs.count >= collectionPage { break }
        } while cursor != "0"
        if pairs.count > collectionPage {
            pairs = Array(pairs.prefix(collectionPage))
        }
        let rows = pairs.enumerated().map { RedisFieldRow(id: $0.offset, primary: $0.element.0, secondary: $0.element.1) }
        return (.table(RedisTableValue(primaryTitle: "字段", secondaryTitle: "值", rows: rows)), total, total > rows.count)
    }

    private static func loadStream(_ client: RedisClient, key: String) async throws -> (RedisDecodedValue, Int?, Bool) {
        let total = try await client.execute(RedisCommand.xlen(key)).integerValue.map(Int.init) ?? 0
        let entries = try await client.execute(RedisCommand.xrevrange(key, count: collectionPage)).elements
        let rows = entries.enumerated().map { item in
            let entry = item.element.elements
            let id = entry.first?.lossyString ?? ""
            let fieldItems: [RESPValue]
            if entry.count >= 2, !entry[1].elements.isEmpty {
                fieldItems = entry[1].elements
            } else {
                fieldItems = Array(entry.dropFirst())
            }
            var parts: [String] = []
            var i = 0
            while i + 1 < fieldItems.count {
                parts.append("\(fieldItems[i].lossyString)=\(fieldItems[i + 1].lossyString)")
                i += 2
            }
            return RedisFieldRow(id: item.offset, primary: id, secondary: parts.joined(separator: "  "))
        }
        return (.table(RedisTableValue(primaryTitle: "ID", secondaryTitle: "字段", rows: rows)), total, total > rows.count)
    }

    private static func loadJSON(_ client: RedisClient, key: String) async throws -> (RedisDecodedValue, Int?, Bool) {
        do {
            let reply = try await client.execute(RedisCommand.jsonGet(key))
            let text = reply.stringContent ?? reply.lossyString
            return (.string(text: prettyJSON(text) ?? text, binary: false), text.count, false)
        } catch RedisClientError.server(let message) where RedisClientError.isUnknownCommand(message) {
            return (.raw("服务器不支持 JSON.GET"), nil, false)
        }
    }

    private static func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }
}
