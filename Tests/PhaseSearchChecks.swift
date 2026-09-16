import Foundation

@main struct PhaseSearchChecks {
    static func main() throws {
        let rows = [
            ["REGION_CD":"L01","INT_NO":"2904","INT_NM":"시청","MAP_NO":"0","A_RING_1_PHASE_CONF_CD":"S194014"],
            ["REGION_CD":"L01","INT_NO":"test","INT_NM":"테스트 전용","MAP_NO":"0","A_RING_1_PHASE_CONF_CD":"P090270"],
            ["REGION_CD":"L01","INT_NO":"test","INT_NM":"테스트 전용","MAP_NO":"1","B_RING_2_PHASE_CONF_CD":"P270090"],
            ["REGION_CD":"L02","INT_NO":"other","A_RING_1_PHASE_CONF_CD":"P090270"],
            ["REGION_CD":"L01","INT_NO":"invalid","A_RING_1_PHASE_CONF_CD":"Punknown"]
        ]
        let search = PedestrianPhaseSearch(rows:rows,complete:false,total:100,pagesRead:1)
        precondition(!search.complete && search.candidates.count == 1)
        precondition(search.candidates[0].phaseCount == 2 && search.candidates[0].maps == ["0","1"])
        let url = SeoulPhaseBasis.url(key:"a%2Bb%3D",name:"",detail:true,page:2)
        let parts = URLComponents(url:url,resolvingAgainstBaseURL:false)!
        precondition(!parts.queryItems!.contains { $0.name == "srchCRNm" })
        precondition(parts.queryItems!.first { $0.name == "serviceKey" }!.value == "a+b=")
        precondition(parts.percentEncodedQuery!.contains("%2B"))
        var accumulator = PlanPageAccumulator(maximumPages:100)
        try accumulator.append(.init(rows:[rows[0]],total:25,pages:25,page:1))
        precondition(!accumulator.isComplete)
        var normal = PlanPageAccumulator()
        do { try normal.append(.init(rows:[rows[0]],total:25,pages:25,page:1)); fatalError("Default limit changed") } catch { }
        print("P search grouping, region/code filtering, partial results and optional query passed")
    }
}
