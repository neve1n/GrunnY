import Foundation

@main struct RunAnnouncementsChecks {
    static func main() throws {
        var splits = RunAnnouncements()
        precondition(splits.update(distance: 990, elapsed: 297, target: 2000, arrived: false).isEmpty)
        let first = splits.update(distance: 1010, elapsed: 303, target: 2000, arrived: false)
        precondition(first == ["1킬로미터를 달렸어요. 이번 구간 페이스는 5분 0초예요."])
        precondition(splits.update(distance: 1010, elapsed: 310, target: 2000, arrived: false).isEmpty)
        let second = splits.update(distance: 2000, elapsed: 665, target: 2000, arrived: false)
        precondition(second[0] == "2킬로미터를 달렸어요. 이번 구간 페이스는 6분 5초예요.", second.description)
        precondition(second[1] == "목표 거리를 달렸어요. 목적지까지 안내를 계속할게요.")
        precondition(splits.update(distance: 2100, elapsed: 700, target: 2000, arrived: false).isEmpty)
        var off = OffRouteAnnouncements()
        let now = Date()
        precondition(off.update(outside: true, at: now) == nil)
        precondition(off.update(outside: true, at: now.addingTimeInterval(5))!.contains("코스에서 벗어났어요"))
        precondition(off.update(outside: true, at: now.addingTimeInterval(34)) == nil)
        precondition(off.update(outside: false, at: now.addingTimeInterval(35))!.contains("코스로 돌아왔어요"))
        precondition(!off.disabled)
        _ = off.update(outside: true, at: now.addingTimeInterval(40))
        for time in [45.0, 75.0, 105.0] { precondition(off.update(outside: true, at: now.addingTimeInterval(time)) != nil) }
        precondition(!off.disabled)
        precondition(off.update(outside: true, at: now.addingTimeInterval(135))!.contains("경로 안내를 종료"))
        precondition(off.disabled)
        precondition(off.update(outside: false, at: now.addingTimeInterval(140)) == nil)
        func evidence(distance: Double = 5000, duration: Double = 1800,
                      gps: Bool = true, plannedTime: Double? = 1800) -> RunCompletionEvidence {
            RunCompletionEvidence(gpsArrived: gps, actualDistance: distance, actualDuration: duration,
                plannedDistance: 5000, plannedDuration: plannedTime, distanceTolerance: 0.05, timeTolerance: 0.10)
        }
        precondition(evidence().missionComplete)
        precondition(evidence(distance: 4750, duration: 1620).missionComplete)
        precondition(evidence(distance: 5250, duration: 1980).missionComplete)
        precondition(!evidence(distance: 4749).missionComplete)
        precondition(!evidence(distance: 5251).missionComplete)
        precondition(!evidence(duration: 1619).missionComplete)
        precondition(!evidence(duration: 1981).missionComplete)
        precondition(!evidence(gps: false).missionComplete)
        precondition(!evidence(plannedTime: nil).missionComplete)
        precondition(!evidence(distance: .nan).missionComplete)
        precondition(evidence().announcement.contains("흐름을 완성"))
        precondition(evidence(gps: false).announcement.contains("기록을 확인"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let record = RunRecord(id: UUID(), startedAt: now, endedAt: now.addingTimeInterval(665),
            distance: 2000, targetDistance: 2000, targetPace: 360, finishReason: "manual", missionComplete: false, points: [])
        try record.save(directory: folder)
        try record.save(directory: folder)
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        precondition(files.count == 1)
        let saved = try JSONDecoder().decode(RunRecord.self, from: Data(contentsOf: files[0]))
        precondition(saved.distance == 2000 && saved.id == record.id)
        print("Split interpolation, once-only target, off-route intervals/return/shutdown, mission evidence and record persistence passed")
    }
}
