import Foundation

struct RouteSignalAssessment: Identifiable {
    let id: UUID
    let distance: Double
    let matches: [CrosswalkMatch]
    let estimate: SignalRouteEstimate
    let reasons: [String: String]

    static func make(id: UUID, distance: Double, matches: [CrosswalkMatch], pace: Int,
                     departure: Date, plans: SeoulPlanCollection?) -> Self {
        let reasons = Dictionary(uniqueKeysWithValues: matches.map { match in
            (match.id, readinessReason(for: match, at: departure.addingTimeInterval(match.metersFromStart / 1000 * Double(pace)), plans: plans))
        })
        // Proximity matches are not confirmed crossings. No provider adapter currently
        // supplies a verified walk-entry window and cycle epoch. Never synthesize either.
        let crossings = matches.map { match in
            SignalWaitEstimator.Crossing(id: match.id, metersFromStart: match.metersFromStart,
                                         timing: nil, unavailableReason: reasons[match.id])
        }
        return Self(id: id, distance: distance, matches: matches,
                    estimate: SignalWaitEstimator.evaluate(distance: distance, pace: pace, departure: departure,
                                                            crossings: crossings, coverageVerified: false), reasons: reasons)
    }

    private static func readinessReason(for match: CrosswalkMatch, at arrival: Date, plans: SeoulPlanCollection?) -> String {
        if match.crosswalk.signalPresence == "무" { return "보행등 미설치 자료 · 실제 횡단 여부 확인 필요" }
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
