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

    func save(directory: URL? = nil) throws {
        let folder = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RunRecords", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: folder.appendingPathComponent(id.uuidString + ".json"), options: .atomic)
    }
}
