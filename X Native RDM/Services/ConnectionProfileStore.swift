import Foundation

nonisolated enum ConnectionProfileStore {
    static func load() -> ConnectionLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ConnectionLibrary(folders: [], profiles: [])
        }
        do {
            let data = try Data(contentsOf: fileURL)
            if let library = try? decoder.decode(ConnectionLibrary.self, from: data) {
                return library
            }
            let profiles = try decoder.decode([ConnectionProfile].self, from: data)
            return ConnectionLibrary(folders: [], profiles: profiles)
        } catch {
            return ConnectionLibrary(folders: [], profiles: [])
        }
    }

    static func save(_ library: ConnectionLibrary) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(library)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static var directoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let current = support.appendingPathComponent("X Native RDM", isDirectory: true)
        let legacy = support.appendingPathComponent("Native RDM", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: current.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: current)
        }
        return current
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("connections.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
