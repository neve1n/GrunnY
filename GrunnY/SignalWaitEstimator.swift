import Foundation

/// Normalized pedestrian timing only. Raw vehicle phase durations/offsets are not inputs.
/// A provider adapter must establish the crossing mapping, absolute cycle anchor,
/// walk-entry intervals (excluding flashing), and validity before constructing this.
struct PedestrianTiming {
    struct WalkWindow { let start: Double; let end: Double }
    let anchor: Date
    let cycle: Double
    let walkWindows: [WalkWindow]
    let validFrom: Date
    let validUntil: Date

    func wait(at arrival: Date) -> Double? {
        guard cycle.isFinite, cycle > 0, cycle <= 3600,
              anchor.timeIntervalSince1970.isFinite,
              validFrom.timeIntervalSince1970.isFinite, validUntil.timeIntervalSince1970.isFinite,
              validFrom < validUntil, arrival >= validFrom, arrival < validUntil,
              !walkWindows.isEmpty else { return nil }
        let windows = walkWindows.sorted { $0.start < $1.start }
        guard windows.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.start < $0.end && $0.end <= cycle }),
              zip(windows, windows.dropFirst()).allSatisfy({ $0.end <= $1.start }) else { return nil }
        let elapsed = arrival.timeIntervalSince(anchor)
        guard elapsed.isFinite else { return nil }
        let phase = (elapsed.truncatingRemainder(dividingBy: cycle) + cycle).truncatingRemainder(dividingBy: cycle)
        if windows.contains(where: { $0.start <= phase && phase < $0.end }) { return 0 }
        let wait = windows.first(where: { $0.start > phase }).map { $0.start - phase }
            ?? (cycle - phase + windows[0].start)
        // Do not extrapolate a schedule through a plan transition or missing next plan.
        guard arrival.addingTimeInterval(wait) < validUntil else { return nil }
        return wait
    }
}

struct SignalRouteEstimate {
    struct Stop: Identifiable {
        let id: String
        let arrival: Date?
        let wait: Double?
        let reason: String?
    }
    let stops: [Stop]
    let totalWait: Double?
    let finish: Date?
    let unavailableReason: String?
}

enum SignalWaitEstimator {
    struct Crossing {
        let id: String
        let metersFromStart: Double
        let timing: PedestrianTiming?
        let unavailableReason: String?
    }

    static func evaluate(distance: Double, pace: Int, departure: Date,
                         crossings: [Crossing], coverageVerified: Bool) -> SignalRouteEstimate {
        guard distance.isFinite, distance > 0, (180...900).contains(pace), departure.timeIntervalSince1970.isFinite,
              Set(crossings.map(\.id)).count == crossings.count,
              crossings.allSatisfy({ $0.metersFromStart.isFinite && $0.metersFromStart >= 0 && $0.metersFromStart <= distance }) else {
            return .init(stops: [], totalWait: nil, finish: nil, unavailableReason: "경로 거리·페이스·시각이 유효하지 않습니다.")
        }
        var accumulated = 0.0
        var unknown = false
        var stops: [SignalRouteEstimate.Stop] = []
        for crossing in crossings.sorted(by: { $0.metersFromStart < $1.metersFromStart }) {
            guard !unknown else {
                stops.append(.init(id: crossing.id, arrival: nil, wait: nil, reason: "앞 신호의 대기시간이 미확인입니다."))
                continue
            }
            let arrival = departure.addingTimeInterval(crossing.metersFromStart / 1000 * Double(pace) + accumulated)
            guard let timing = crossing.timing, let wait = timing.wait(at: arrival) else {
                stops.append(.init(id: crossing.id, arrival: arrival, wait: nil,
                                   reason: crossing.unavailableReason ?? "도착 시각에 유효한 보행신호 계획이 없습니다."))
                unknown = true
                continue
            }
            accumulated += wait
            stops.append(.init(id: crossing.id, arrival: arrival, wait: wait, reason: nil))
        }
        let complete = coverageVerified && !unknown
        return .init(stops: stops, totalWait: complete ? accumulated : nil,
                     finish: complete ? departure.addingTimeInterval(distance / 1000 * Double(pace) + accumulated) : nil,
                     unavailableReason: !coverageVerified ? "실제 횡단 구간과 신호 데이터의 전체 범위가 검증되지 않았습니다." : (unknown ? "대기시간을 계산할 수 없는 신호가 있습니다." : nil))
    }

    /// Unknown routes are not zero-wait routes. Recommend only when every candidate is comparable.
    static func bestIndex(estimates: [SignalRouteEstimate], distances: [Double], target: Double) -> Int? {
        guard !estimates.isEmpty, estimates.count == distances.count, target.isFinite, target > 0,
              distances.allSatisfy({ $0.isFinite && $0 > 0 }),
              estimates.allSatisfy({ $0.totalWait != nil && $0.totalWait!.isFinite && $0.totalWait! >= 0 }) else { return nil }
        return estimates.indices.min {
            let left = estimates[$0].totalWait!, right = estimates[$1].totalWait!
            return left == right ? abs(distances[$0] - target) < abs(distances[$1] - target) : left < right
        }
    }
}
