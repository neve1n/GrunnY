import Foundation

struct RouteSignalAssessment: Identifiable {
    let id: UUID
    let distance: Double
    let matches: [CrosswalkMatch]
    let estimate: SignalRouteEstimate
    let reasons: [String: String]

    static func make(id: UUID, distance: Double, matches: [CrosswalkMatch], pace: Int,
                     departure: Date, plans: SeoulPlanCollection?, signalRows: [SeoulSignalRow] = [],
                     verifiedCycles: [String: StatisticalSignalCycle] = [:], coverageVerified: Bool = false) -> Self {
        if !coverageVerified && verifiedCycles.isEmpty {
            return cycleBased(id: id, distance: distance, matches: matches, pace: pace,
                              departure: departure, plans: plans, signalRows: signalRows)
        }
        let reasons = Dictionary(uniqueKeysWithValues: matches.map { match in
            (match.id, readinessReason(for: match, at: departure.addingTimeInterval(match.metersFromStart / 1000 * Double(pace)), plans: plans, signalRows: signalRows))
        })
        // Coordinates only propose a link. Neither a matching name nor a recent
        // observation establishes route coverage or a future walk-entry window.
        let crossings = matches.map { match in
            SignalWaitEstimator.Crossing(id: match.id, metersFromStart: match.metersFromStart,
                                         timing: nil, unavailableReason: reasons[match.id])
        }
        return Self(id: id, distance: distance, matches: matches,
                    estimate: SignalWaitEstimator.evaluateAverage(distance: distance, pace: pace, departure: departure,
                        crossings: crossings, cycles: verifiedCycles, coverageVerified: coverageVerified), reasons: reasons)
    }

    /// Explicitly approximate: nearby facilities stand in for route crossings,
    /// and red is assumed to occupy half the cycle. No pedestrian-phase claim.
    private static func cycleBased(id: UUID, distance: Double, matches: [CrosswalkMatch],
                                   pace: Int, departure: Date, plans: SeoulPlanCollection?, signalRows: [SeoulSignalRow]) -> Self {
        var reasons: [String: String] = [:]
        var stops: [SignalRouteEstimate.Stop] = []
        var total = 0.0
        var observedCount = 0
        var missing = !distance.isFinite || distance <= 0
            || !(180...900).contains(pace) || !departure.timeIntervalSince1970.isFinite
            || Set(matches.map(\.id)).count != matches.count
            || matches.contains { !$0.metersFromStart.isFinite || $0.metersFromStart < 0 || $0.metersFromStart > distance }
        for match in matches.sorted(by: { $0.metersFromStart < $1.metersFromStart }) {
            if match.crosswalk.signalPresence == "무" {
                reasons[match.id] = "신호등 미설치 · 신호 대기 계산에서 제외"
                continue
            }
            let arrival = missing ? nil : departure.addingTimeInterval(match.metersFromStart / 1000 * Double(pace) + total)
            var value = cycleWait(for: match, at: arrival ?? departure, plans: plans)
            let connection = SignalTimingConnection.inspect(crosswalk: match.crosswalk, rows: signalRows,
                catalog: SignalIntersectionCatalog.bundled, allCrosswalks: CrosswalkCatalog.bundled?.crosswalks ?? [])
            if let arrival, let wait = connection.observedGreenWait(at: arrival) {
                value = (wait, "예상 도착이 초록불 관측 구간 안 · 좌표 기반 횡단보도 대응 가정")
                observedCount += 1
            }
            reasons[match.id] = value.reason
                + "\n" + connection.detail
                + "\n" + SignalTimingConnection.planDetail(for: match.crosswalk, plans: plans, at: arrival ?? departure)
            if let arrival, let wait = value.wait {
                total += wait
                stops.append(.init(id: match.id, arrival: arrival, wait: wait, reason: nil))
            } else {
                missing = true
                stops.append(.init(id: match.id, arrival: arrival, wait: nil, reason: value.wait == nil ? value.reason : "앞 구간의 주기 미확인"))
            }
        }
        let usesDefault = reasons.values.contains { $0.contains("기본 주기") }
        let usesAverage = reasons.values.contains { $0.contains("평균") }
        let note = matches.isEmpty ? "검출된 횡단보도 기준 0초 · 자료에 없는 시설은 미반영"
            : "빨간불 50% 가정" + (usesDefault ? " · 기본 주기 120초 사용" : "")
                + (usesAverage ? " · 수집 주기 평균 사용" : "")
                + (observedCount > 0 ? " · 초록불 관측 구간 \(observedCount)곳 반영" : "")
        let estimate = SignalRouteEstimate(stops: stops, totalWait: missing ? nil : total,
            finish: missing ? nil : departure.addingTimeInterval(distance / 1000 * Double(pace) + total),
            unavailableReason: missing ? "코스 거리·페이스·시각이 유효하지 않습니다." : nil,
            method: .cycleHeuristic, assumptionNote: note)
        return Self(id: id, distance: distance, matches: matches, estimate: estimate, reasons: reasons)
    }

    private static func cycleWait(for match: CrosswalkMatch, at arrival: Date,
                                  plans: SeoulPlanCollection?) -> (wait: Double?, reason: String) {
        let fallback = fallbackCycle(plans: plans)
        if match.crosswalk.signalPresence != "유" {
            return (fallback.cycle / 8, "설치 여부 미확인 · 신호등 있음으로 가정 · " + fallback.reason)
        }
        guard let plans else { return (fallback.cycle / 8, fallback.reason) }
        let name = match.crosswalk.name.filter { !$0.isWhitespace }
        guard !name.isEmpty else { return (fallback.cycle / 8, "교차로 이름 미확인 · " + fallback.reason) }
        let rows = plans.operations.filter { ($0["INT_NM"] ?? "").filter { !$0.isWhitespace } == name }
        let ids = Set(rows.compactMap { $0["INT_NO"] }.filter { !$0.isEmpty })
        guard ids.count == 1, let intersection = ids.first else {
            return (fallback.cycle / 8, "개별 주기 연결 없음 · " + fallback.reason)
        }
        if case .candidate(let row) = plans.selection(intersectionID: intersection, at: arrival),
           let cycle = Double(row["INT_OPER_CYCLE_VAL"] ?? ""), cycle.isFinite, cycle > 0, cycle <= 3600 {
            return (cycle / 8, "주기 \(Int(cycle))초 ÷ 8 · 빨간불 50%·무작위 도착·실제 횡단 가정")
        }
        // If the active schedule cannot be resolved, use the collected schedule
        // values equally, explicitly as a model rather than the current cycle.
        let cycles = validCycles(rows)
        guard !cycles.isEmpty else {
            return (fallback.cycle / 8, "개별 주기 없음 · " + fallback.reason)
        }
        let cycle = cycles.reduce(0, +) / Double(cycles.count)
        return (cycle / 8, "등록 운영주기 평균 \(Int(cycle.rounded()))초 ÷ 8 · 현재 적용 주기 미확정 · 빨간불 50%·실제 횡단 가정")
    }

    private static func validCycles(_ rows: [[String: String]]) -> [Double] {
        rows.compactMap { Double($0["INT_OPER_CYCLE_VAL"] ?? "") }
            .filter { $0.isFinite && $0 > 0 && $0 <= 3600 }
    }

    private static func fallbackCycle(plans: SeoulPlanCollection?) -> (cycle: Double, reason: String) {
        // Average each intersection first so a controller with more time slots
        // does not outweigh the other available signals.
        let grouped = Dictionary(grouping: plans?.operations.filter {
            !($0["INT_NO"] ?? "").isEmpty
        } ?? [], by: { $0["INT_NO"]! })
        let means = grouped.values.compactMap { rows -> Double? in
            let values = validCycles(rows)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        guard !means.isEmpty else {
            return (120, "수집된 주기 없음 · 기본 주기 120초 가정 ÷ 8")
        }
        let mean = means.reduce(0, +) / Double(means.count)
        return (mean, "다른 교차로 \(means.count)곳의 평균 주기 \(Int(mean.rounded()))초 대입 ÷ 8")
    }

    private static func readinessReason(for match: CrosswalkMatch, at arrival: Date, plans: SeoulPlanCollection?, signalRows: [SeoulSignalRow]) -> String {
        if match.crosswalk.signalPresence == "무" { return "보행등 미설치 자료 · 실제 횡단 여부 확인 필요" }
        if !signalRows.isEmpty {
            return "잔여시간 관측만으로 전체 빨간불 길이·주기를 알 수 없음 · 보행신호 대응과 전체 주기 필요"
        }
        guard let plans else { return "운영·요일·특수일·예약계획 미수집" }
        guard let basis = plans.basis else { return "교차로 기반정보 미수집" }
        let name = match.crosswalk.name.filter { !$0.isWhitespace }
        guard !name.isEmpty else { return "교차로 이름이 없어 기반정보 대응 미확인" }
        let candidates = basis.intersections.filter { ($0["INT_NM"] ?? "").filter { !$0.isWhitespace } == name }
        guard candidates.count == 1, let id = candidates[0]["INT_NO"] else { return "수집한 기반정보에서 이름이 일치하는 교차로를 하나로 정할 수 없음" }
        let configurations = basis.configurations(for: id)
        guard !configurations.isEmpty else { return "교차로 현시 구성정보 없음" }
        let hasPedestrian = configurations.contains { row in
            ["A", "B"].contains { ring in
                (1...8).contains { PolicePhaseCode(row["\(ring)_RING_\($0)_PHASE_CONF_CD"] ?? "")?.isPedestrian == true }
            }
        }
        guard hasPedestrian else { return "수집한 맵에 해석 가능한 P 보행현시 없음" }
        if case .unavailable(let reason) = plans.selection(intersectionID: id, at: arrival) { return reason }
        return "보행현시 존재 · 횡단보도 대응, 적용 맵, 녹색 구간과 주기 기준시각 검증 필요"
    }
}
