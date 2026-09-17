import Foundation

struct RunRecord: Codable {
    struct Point: Codable {
        let latitude: Double
        let longitude: Double
        let timestamp: Date
    }
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distance: Double
    let targetDistance: Double?
    let targetPace: Int?
    let finishReason: String
    let missionComplete: Bool
    let points: [Point]

    static func storageDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RunRecords", isDirectory: true)
    }

    static func loadAll(directory: URL? = nil) throws -> [RunRecord] {
        let folder = try directory ?? storageDirectory()
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(RunRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func delete(directory: URL? = nil) throws {
        let folder = try directory ?? Self.storageDirectory()
        try FileManager.default.removeItem(at: folder.appendingPathComponent(id.uuidString + ".json"))
    }

    static func deleteAll(directory: URL? = nil) throws {
        let folder = try directory ?? storageDirectory()
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func save(directory: URL? = nil) throws {
        let folder = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RunRecords", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: folder.appendingPathComponent(id.uuidString + ".json"), options: .atomic)
    }
}
