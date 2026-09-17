import Foundation

/// Uses only the observed state interval, never repeats a countdown as a cycle.
struct SignalTimingConnection {
    let observedAt: Date?
    let stateEndsAt: Date?
    let state: String?
    let detail: String

    func observedGreenWait(at arrival: Date) -> Double? {
        guard state == "protected-Movement-Allowed",
              let observedAt, let stateEndsAt,
              arrival >= observedAt, arrival < stateEndsAt.addingTimeInterval(-2) else { return nil }
        return 0
    }

    static func inspect(crosswalk: Crosswalk, rows: [SeoulSignalRow],
                        catalog: SignalIntersectionCatalog?, allCrosswalks: [Crosswalk],
                        now: Date = .now) -> Self {
        func unavailable(_ detail: String) -> Self {
            Self(observedAt: nil, stateEndsAt: nil, state: nil, detail: detail)
        }
        guard let catalog, let intersection = catalog.link(for: crosswalk) else {
            return unavailable("실시간 교차로 연결 후보 없음")
        }
        guard let direction = catalog.directionCandidate(for: crosswalk, at: intersection, allCrosswalks: allCrosswalks) else {
            return unavailable("보행신호 방향을 하나로 정할 수 없음")
        }
        let candidates = rows.filter { $0.intersectionID == intersection.id }
        guard let latestDate = candidates.compactMap(\.observedAt).max() else {
            return unavailable("연결된 교차로의 관측 시각 없음")
        }
        let age = now.timeIntervalSince(latestDate)
        guard age >= 0, age <= 30 else {
            return unavailable("관측값이 30초 이상 지났거나 미래 시각임")
        }
        let observations = candidates.filter { $0.observedAt == latestDate }
            .flatMap(\.pedestrianSignals).filter { $0.direction == direction }
        guard let observation = observations.first,
              observations.allSatisfy({ $0.state == observation.state && $0.remainingRaw == observation.remainingRaw }),
              let remaining = observation.remainingSeconds, remaining > 0,
              let state = observation.state,
              ["protected-Movement-Allowed", "stop-And-Remain", "protected-clearance", "permissive-clearance"].contains(state) else {
            return unavailable("보행신호 상태·잔여시간 누락 또는 응답 충돌")
        }
        let end = latestDate.addingTimeInterval(remaining)
        guard end > now else { return unavailable("관측 신호의 잔여 구간이 이미 끝남") }
        return Self(observedAt: latestDate, stateEndsAt: end, state: state,
                    detail: "관측 \(latestDate.formatted(date: .omitted, time: .standard)) → 상태 전환 예정 \(end.formatted(date: .omitted, time: .standard)) · 이름·좌표 기반 방향 후보 · 다음 주기 반복 예측 안 함")
    }

    static func planDetail(for crosswalk: Crosswalk, plans: SeoulPlanCollection?, at date: Date) -> String {
        guard let plans else { return "운영계획 미수집 · 자정·옵셋 연결 확인 전" }
        let name = crosswalk.name.filter { !$0.isWhitespace }
        let ids = Set(plans.operations.filter { !$0.isEmpty && !name.isEmpty && ($0["INT_NM"] ?? "").filter { !$0.isWhitespace } == name }.compactMap { $0["INT_NO"] })
        guard ids.count == 1, let id = ids.first else { return "운영계획의 교차로 연결 미확정" }
        switch plans.selection(intersectionID: id, at: date) {
        case .unavailable(let reason): return "적용 계획 미확정: " + reason
        case .candidate(let row):
            let configurations = plans.basis?.configurations(for: id) ?? []
            let pedestrianCount = configurations.reduce(0) { $0 + PedestrianPhaseSearch.pedestrianCount($1) }
            return "자정 기준 규격 · 주기 \(row["INT_OPER_CYCLE_VAL"] ?? "?")초 · 옵셋 \(row["INT_OPER_OFFSET_VAL"] ?? "?")초. "
                + (pedestrianCount == 0 ? "연결된 P 보행현시 없음." : "P 보행현시 \(pedestrianCount)건 · 적용 맵·주현시·진입 가능 구간 미확정.")
                + " 자정+옵셋을 보행 초록불 시작으로 사용하지 않음."
        }
    }
}
