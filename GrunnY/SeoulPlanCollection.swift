import Foundation

enum SeoulPlanKind: String, CaseIterable, Hashable {
    case operation = "PlanCROPInfo", weekday = "PlanCRWDInfo", holiday = "PlanCRHDInfo", reservation = "PlanCRRSInfo"
    var endpoint: String { "get" + rawValue }
    var label: String {
        switch self {
        case .operation: "시간대 운영계획"
        case .weekday: "요일계획"
        case .holiday: "특수일계획"
        case .reservation: "예약계획"
        }
    }
}

struct PlanPageAccumulator {
    var maximumPages = 20
    init(maximumPages: Int = 20) { self.maximumPages = maximumPages }
    private(set) var rows: [[String: String]] = []
    private(set) var expectedTotal: Int?
    private(set) var expectedPages: Int?
    private(set) var nextPage = 1
    private var seen: Set<String> = []
    var isComplete: Bool {
        guard let expectedTotal, let expectedPages else { return false }
        return rows.count == expectedTotal && (expectedTotal == 0 || nextPage > expectedPages)
    }
    mutating func append(_ page: SeoulPlanPage) throws {
        guard !isComplete, page.pages <= maximumPages,
              (page.total == 0 && nextPage == 1 && page.page <= 1) || page.page == nextPage else { throw PlanFailure.incomplete }
        if let expectedTotal, let expectedPages {
            guard expectedTotal == page.total, expectedPages == page.pages else { throw PlanFailure.incomplete }
        }
        // Validate before committing so a rejected page cannot advance the cursor or
        // leave a partially mutated row set behind.
        var nextSeen = seen
        for row in page.rows {
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            guard nextSeen.insert(data.base64EncodedString()).inserted else { throw PlanFailure.incomplete }
        }
        let newCount = rows.count + page.rows.count
        guard newCount <= page.total else {
            throw PlanFailure.countMismatch(page: page.page, received: page.rows.count, accumulated: newCount, declared: page.total)
        }
        if page.page >= page.pages && newCount != page.total {
            throw PlanFailure.countMismatch(page: page.page, received: page.rows.count, accumulated: newCount, declared: page.total)
        }
        expectedTotal = page.total
        expectedPages = page.pages
        seen = nextSeen
        rows.append(contentsOf: page.rows)
        nextPage += 1
    }

}

struct SeoulPlanCollection {
    let query: String
    let fetchedAt: Date
    let tables: [SeoulPlanKind: [[String: String]]]
    var basis: SeoulPhaseBasis? = nil
    var operations: [[String: String]] { tables[.operation] ?? [] }
    var intersectionIDs: [String] { Set(operations.compactMap { $0["INT_NO"] }).sorted() }

    /// Plan candidate only: no claim of live controller state or pedestrian phase mapping.
    func selection(intersectionID: String, at date: Date) -> PlanSelection {
        guard SeoulPlanKind.allCases.allSatisfy({ tables[$0] != nil }) else { return .unavailable("전체 계획 데이터가 없습니다.") }
        let rows = { (kind: SeoulPlanKind) in tables[kind]!.filter { $0["INT_NO"] == intersectionID } }
        // Reservation wildcard/overnight semantics are not established. Do not ignore them.
        if rows(.reservation).contains(where: { row in
            guard let code = Int(row["RESRV_CONTRL_CD"] ?? "") else { return true }
            return code != 0
        }) { return .unavailable("예약 제어가 등록돼 있어 적용 조건 검증이 필요합니다.") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let components = calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: date)
        let dayCode = ((components.weekday! + 5) % 7) + 1 // provider: Monday 1 ... Sunday 7
        let special = rows(.holiday)
        // Providers expose HOLY_PLAN and HOLYDD_PLAN aliases. Unknown values are not ignored.
        guard special.allSatisfy({ r in
            if Int(r["INT_PLAN_NO"] ?? "") == 0 { return true }
            guard let m = Int(r["HOLY_PLAN_MM"] ?? r["HOLYDD_PLAN_MM"] ?? ""),
                  let d = Int(r["HOLY_PLAN_DD"] ?? r["HOLYDD_PLAN_DD"] ?? "") else { return false }
            return (1...12).contains(m) && (1...31).contains(d)
        }) else { return .unavailable("특수일 계획에 해석하지 못한 날짜가 있습니다.") }
        let holidays = special.filter {
            Int($0["INT_PLAN_NO"] ?? "") != 0 &&
            Int($0["HOLY_PLAN_MM"] ?? $0["HOLYDD_PLAN_MM"] ?? "") == components.month &&
            Int($0["HOLY_PLAN_DD"] ?? $0["HOLYDD_PLAN_DD"] ?? "") == components.day
        }
        // Avoid assuming precedence absent a verified controller rule.
        if !holidays.isEmpty { return .unavailable("해당 날짜에 특수일 계획이 있습니다. 요일계획과의 적용 우선순위 검증이 필요합니다.") }
        let weekdays = rows(.weekday).filter { Int($0["PLAN_DY"] ?? "") == dayCode }
        guard weekdays.count == 1, let plan = weekdays.first?["INT_PLAN_NO"], Int(plan) ?? 0 > 0 else {
            return .unavailable("해당 요일의 계획이 없거나 중복됩니다.")
        }
        let operations = rows(.operation).filter { $0["INT_PLAN_NO"] == plan }
        var times: [(Int, [String: String])] = []
        for row in operations {
            guard let hour = Int(row["OPER_PLAN_HH"] ?? ""), (0...23).contains(hour),
                  let minute = Int(row["OPER_PLAN_MI"] ?? ""), (0...59).contains(minute) else {
                return .unavailable("운영계획의 적용 시각이 유효하지 않습니다.")
            }
            times.append((hour * 60 + minute, row))
        }
        let target = components.hour! * 60 + components.minute!
        guard let start = times.filter({ $0.0 <= target }).map(\.0).max() else {
            return .unavailable("첫 적용 시각 이전입니다. 전날부터 이어지는 계획 검증이 필요합니다.")
        }
        let matching = times.filter { $0.0 == start }
        guard matching.count == 1, let row = matching.first?.1,
              let cycle = Int(row["INT_OPER_CYCLE_VAL"] ?? ""), cycle > 0,
              let offset = Int(row["INT_OPER_OFFSET_VAL"] ?? ""), offset >= 0, offset < cycle else {
            return .unavailable("운영계획이 중복되거나 주기·옵셋이 유효하지 않습니다.")
        }
        for ring in ["A", "B"] {
            let values = (1...8).compactMap { Int(row["\(ring)_RING_\($0)_PHASE_VAL"] ?? "") }
            guard values.count == 8, values.allSatisfy({ $0 >= 0 }), values.reduce(0,+) == cycle else {
                return .unavailable("현시 합계와 주기가 일치하지 않아 검증이 필요합니다.")
            }
        }
        return .candidate(row)
    }
}

enum PlanSelection {
    case candidate([String: String])
    case unavailable(String)
}

/// Police IDs are joined only within the police services, never with T-GIS/T-Data IDs.
struct SeoulPhaseBasis {
    let fetchedAt: Date
    let intersections: [[String: String]]
    let configurations: [[String: String]]

    func configurations(for id: String) -> [[String: String]] {
        guard intersections.filter({ $0["REGION_CD"] == "L01" && $0["INT_NO"] == id }).count == 1 else { return [] }
        return configurations.filter { $0["REGION_CD"] == "L01" && $0["INT_NO"] == id }
    }

    static func url(key: String, name: String, detail: Bool, page: Int) -> URL {
        // Shared key/query encoding; endpoint and XML records are specified separately.
        var parts = URLComponents(url: SeoulPlanPage.url(key: key, name: name, page: page), resolvingAgainstBaseURL: false)!
        parts.path = "/1320000/CrossRoadInfoService/getCrossRoadInfo\(detail ? "Detail" : "List")"
        if name.isEmpty {
            parts.queryItems?.removeAll { $0.name == "srchCRNm" }
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return parts.url!
    }
}

struct PolicePhaseCode {
    let movement: String
    let entryAngle: Int
    let exitAngle: Int
    var isPedestrian: Bool { movement == "P" }
    var label: String {
        let name = ["S": "직진", "L": "좌회전", "P": "보행자"][movement]!
        return "\(name) · 진입 \(entryAngle)° / 진출 \(exitAngle)°"
    }

    init?(_ raw: String) {
        let bytes = Array(raw.utf8)
        guard bytes.count == 7, [83, 76, 80].contains(bytes[0]),
              bytes.dropFirst().allSatisfy({ (48...57).contains($0) }),
              let entry = Int(String(decoding: bytes[1...3], as: UTF8.self)),
              let exit = Int(String(decoding: bytes[4...6], as: UTF8.self)),
              (0..<360).contains(entry), (0..<360).contains(exit) else { return nil }
        movement = String(decoding: bytes[0...0], as: UTF8.self)
        entryAngle = entry
        exitAngle = exit
    }
}


struct PedestrianPhaseSearch {
    struct Candidate: Identifiable {
        let id: String
        let name: String
        let maps: [String]
        let phaseCount: Int
    }
    var rows: [[String: String]] = []
    var complete = false
    var total = 0
    var pagesRead = 0

    var candidates: [Candidate] {
        let grouped = Dictionary(grouping: rows.filter { row in
            row["REGION_CD"] == "L01" && !(row["INT_NO"] ?? "").isEmpty && Self.pedestrianCount(row) > 0
        }, by: { $0["INT_NO"]! })
        return grouped.map { id, rows in
            Candidate(id: id, name: rows.first?["INT_NM"] ?? "", maps: Set(rows.compactMap { $0["MAP_NO"] }).sorted(),
                      phaseCount: rows.reduce(0) { $0 + Self.pedestrianCount($1) })
        }.sorted { $0.id < $1.id }
    }

    static func pedestrianCount(_ row: [String: String]) -> Int {
        ["A", "B"].reduce(0) { sum, ring in
            sum + (1...8).filter { PolicePhaseCode(row["\(ring)_RING_\($0)_PHASE_CONF_CD"] ?? "")?.isPedestrian == true }.count
        }
    }
}
