import Foundation

@main struct PlanCollectionChecks {
    static func main() throws {
        var acc = PlanPageAccumulator()
        let a = ["INT_NO":"1", "INT_PLAN_IDX_NO":"1"]
        let b = ["INT_NO":"1", "INT_PLAN_IDX_NO":"2"]
        try acc.append(.init(rows: [a], total: 2, pages: 2, page: 1))
        precondition(!acc.isComplete)
        try acc.append(.init(rows: [b], total: 2, pages: 2, page: 2))
        precondition(acc.isComplete && acc.rows.count == 2)
        for bad in [SeoulPlanPage(rows: [a], total: 2, pages: 2, page: 2),
                    SeoulPlanPage(rows: [b], total: 3, pages: 2, page: 2),
                    SeoulPlanPage(rows: [b], total: 2, pages: 2, page: 1)] {
            var test = PlanPageAccumulator()
            try test.append(.init(rows: [a], total: 2, pages: 2, page: 1))
            do { try test.append(bad); fatalError("Must reject incomplete/duplicate/drift") } catch { }
        }
        var atomic = PlanPageAccumulator()
        try atomic.append(.init(rows: [a], total: 3, pages: 2, page: 1))
        do {
            try atomic.append(.init(rows: [b], total: 3, pages: 2, page: 2))
            fatalError("Must reject final count mismatch")
        } catch {
            precondition((error as? PlanFailure)?.errorDescription?.contains("누적 2건") == true)
        }
        precondition(atomic.nextPage == 2 && atomic.rows == [a] && !atomic.isComplete)
        let c = ["INT_NO":"1", "INT_PLAN_IDX_NO":"3"]
        try atomic.append(.init(rows: [b,c], total: 3, pages: 2, page: 2))
        precondition(atomic.isComplete)
        var empty = PlanPageAccumulator()
        try empty.append(.init(rows: [], total: 0, pages: 0, page: 0))
        precondition(empty.isComplete)
        let instant = ISO8601DateFormatter().date(from: "2026-09-17T00:00:00Z")! // Thursday 09:00 KST
        func operation(_ index: String, _ hour: String) -> [String:String] {
            var r = ["INT_NO":"1", "INT_PLAN_NO":"2", "INT_PLAN_IDX_NO":index, "OPER_PLAN_HH":hour,
                     "OPER_PLAN_MI":"0", "INT_OPER_CYCLE_VAL":"120", "INT_OPER_OFFSET_VAL":"59"]
            for ring in ["A","B"] { for phase in 1...8 { r["\(ring)_RING_\(phase)_PHASE_VAL"] = phase == 1 ? "120" : "0" } }
            return r
        }
        let tables: [SeoulPlanKind:[[String:String]]] = [.operation:[operation("1","5"),operation("2","9")],
            .weekday:[["INT_NO":"1","PLAN_DY":"4","INT_PLAN_NO":"2"]], .holiday:[], .reservation:[]]
        func select(_ t: [SeoulPlanKind:[[String:String]]], date: Date = instant) -> PlanSelection {
            SeoulPlanCollection(query:"fixture",fetchedAt:instant,tables:t).selection(intersectionID:"1",at:date)
        }
        guard case .candidate(let row) = select(tables) else { fatalError("Must choose plan") }
        precondition(row["INT_PLAN_IDX_NO"] == "2")
        var holiday = tables; holiday[.holiday] = [["INT_NO":"1","HOLY_PLAN_MM":"9","HOLY_PLAN_DD":"17","INT_PLAN_NO":"3"]]
        var reserved = tables; reserved[.reservation] = [["INT_NO":"1","RESRV_CONTRL_CD":"5"]]
        var incomplete = tables; incomplete[.weekday] = nil
        var inconsistent = tables; inconsistent[.operation]![1]["A_RING_1_PHASE_VAL"] = "119"
        for blocked in [holiday,reserved,incomplete,inconsistent] {
            guard case .unavailable = select(blocked) else { fatalError("Must block unknown plan") }
        }
        let beforeStart = ISO8601DateFormatter().date(from:"2026-09-16T16:00:00Z")!
        guard case .unavailable = select(tables,date:beforeStart) else { fatalError("No invented midnight fallback") }
        let wd = Data("<PlanCrossRoadInfoService><Header><resultCode>0</resultCode><totCount>1</totCount><totPage>1</totPage><pageNo>1</pageNo></Header><PlanCRWDInfo><REGION_CD>L01</REGION_CD><INT_NO>1</INT_NO><PLAN_DY>4</PLAN_DY><INT_PLAN_NO>2</INT_PLAN_NO></PlanCRWDInfo></PlanCrossRoadInfoService>".utf8)
        precondition(tryDecode(wd))
        print("Pagination, KST weekday/time, special/reservation and incomplete-data checks passed")
    }
    static func tryDecode(_ data: Data) -> Bool { (try? SeoulPlanPage.decode(data,kind:.weekday).rows.first?["PLAN_DY"]) == "4" }
}
