import Foundation

struct RunAnnouncements {
    private var previousDistance = 0.0
    private var previousElapsed = 0.0
    private var lastSplitElapsed = 0.0
    private var nextKilometer = 1
    private var targetAnnounced = false

    mutating func update(distance: Double, elapsed: Double, target: Double?, arrived: Bool) -> [String] {
        guard distance.isFinite, elapsed.isFinite, distance >= previousDistance, elapsed >= previousElapsed else { return [] }
        var result: [String] = []
        while distance >= Double(nextKilometer) * 1000 {
            let fraction = (Double(nextKilometer) * 1000 - previousDistance) / max(0.001, distance - previousDistance)
            let boundaryTime = previousElapsed + fraction * (elapsed - previousElapsed)
            let seconds = max(0, Int((boundaryTime - lastSplitElapsed).rounded()))
            result.append("\(nextKilometer)킬로미터를 달렸어요. 이번 구간 페이스는 \(seconds / 60)분 \(seconds % 60)초예요.")
            lastSplitElapsed = boundaryTime
            nextKilometer += 1
        }
        if let target, target > 0, distance >= target, !targetAnnounced {
            targetAnnounced = true
            if !arrived { result.append("목표 거리를 달렸어요. 목적지까지 안내를 계속할게요.") }
        }
        previousDistance = distance; previousElapsed = elapsed
        return result
    }
}

struct OffRouteAnnouncements {
    private(set) var isOffRoute = false
    private(set) var disabled = false
    private var count = 0
    private var lastAnnouncement: Date?
    private var firstOutside: Date?
    var interval: TimeInterval = 30
    var maximumWarnings = 3

    mutating func update(outside: Bool, at date: Date) -> String? {
        if !outside {
            firstOutside = nil
            guard isOffRoute else { return nil }
            isOffRoute = false
            count = 0; lastAnnouncement = nil
            // The maximum-warning shutdown is permanent for this run.
            return disabled ? nil : "코스로 돌아왔어요. 안내를 계속할게요."
        }
        if firstOutside == nil { firstOutside = date }
        guard !disabled, date.timeIntervalSince(firstOutside!) >= 5 else { return nil }
        if let lastAnnouncement, date.timeIntervalSince(lastAnnouncement) < interval { return nil }
        self.lastAnnouncement = date
        isOffRoute = true
        if count >= maximumWarnings {
            disabled = true
            return "경로 안내를 종료할게요. 러닝 기록은 계속돼요."
        }
        count += 1
        return count == 1 ? "코스에서 벗어났어요. 경로를 확인해 주세요." : "아직 코스에서 벗어나 있어요."
    }
}

struct RunCompletionEvidence {
    let gpsArrived: Bool
    let actualDistance: Double
    let actualDuration: TimeInterval
    let plannedDistance: Double?
    let plannedDuration: TimeInterval?
    let distanceTolerance: Double
    let timeTolerance: Double

    var missionComplete: Bool {
        gpsArrived
            && within(actualDistance, expected: plannedDistance, tolerance: distanceTolerance)
            && within(actualDuration, expected: plannedDuration, tolerance: timeTolerance)
    }

    private func within(_ actual: Double, expected: Double?, tolerance: Double) -> Bool {
        guard actual.isFinite, actual >= 0, let expected, expected.isFinite, expected > 0,
              tolerance.isFinite, (0...1).contains(tolerance) else { return false }
        return abs(actual - expected) <= expected * tolerance + 0.000001
    }

    var announcement: String {
        missionComplete ? "목적지에 도착했어요. 오늘의 흐름을 완성했어요."
            : "목적지에 도착했어요. 러닝 기록을 확인해 보세요."
    }
}
