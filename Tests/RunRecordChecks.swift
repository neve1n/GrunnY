import Foundation

@main struct RunRecordChecks {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        precondition(tryEmpty(folder))
        let now = Date()
        let first = RunRecord(id: UUID(), startedAt: now, endedAt: now.addingTimeInterval(120), distance: 300,
            targetDistance: 5000, targetPace: 360, finishReason: "manual", missionComplete: false,
            points: [.init(latitude: 37.5, longitude: 127, timestamp: now)])
        let second = RunRecord(id: UUID(), startedAt: now.addingTimeInterval(300), endedAt: now.addingTimeInterval(600),
            distance: 700, targetDistance: 5000, targetPace: 360, finishReason: "manual", missionComplete: false, points: [])
        try first.save(directory: folder); try second.save(directory: folder)
        let records = try RunRecord.loadAll(directory: folder)
        precondition(records.map(\.id) == [second.id, first.id])
        precondition(records[1].points.count == 1)
        try first.delete(directory: folder)
        let remaining = try RunRecord.loadAll(directory: folder)
        precondition(remaining.count == 1 && remaining[0].id == second.id)
        try RunRecord.deleteAll(directory: folder)
        precondition(tryEmpty(folder))
        try RunRecord.deleteAll(directory: folder)
        print("Record save/load order, GPS retention, individual/all deletion and empty storage passed")
    }
    static func tryEmpty(_ folder: URL) -> Bool { (try? RunRecord.loadAll(directory: folder).isEmpty) == true }
}
