import Foundation

@main struct RouteAssessmentChecks {
    static func main() {
        let crossing = Crosswalk(id:"fixture",district:"",intersectionID:"different-system",name:"시청",signalPresence:"유",latitude:37.56,longitude:126.97)
        let match = CrosswalkMatch(crosswalk:crossing,metersFromStart:100,offsetMeters:1,visit:0)
        func assess(_ matches:[CrosswalkMatch] = [match], _ plans:SeoulPlanCollection? = nil) -> RouteSignalAssessment {
            .make(id:UUID(),distance:1000,matches:matches,pace:300,departure:Date(),plans:plans)
        }
        precondition(assess().estimate.totalWait == nil)
        precondition(assess().reasons[match.id]!.contains("미수집"))
        precondition(assess([]).estimate.totalWait == nil)
        var plans = SeoulPlanCollection(query:"시청",fetchedAt:Date(),tables:[.operation:[],.weekday:[],.holiday:[],.reservation:[]])
        precondition(assess([match],plans).reasons[match.id] == "교차로 기반정보 미수집")
        plans.basis = SeoulPhaseBasis(fetchedAt:Date(),intersections:[["REGION_CD":"L01","INT_NO":"2904","INT_NM":"시청"]],configurations:[["REGION_CD":"L01","INT_NO":"2904","MAP_NO":"0","A_RING_1_PHASE_CONF_CD":"S170350"]])
        precondition(assess([match],plans).reasons[match.id]!.contains("P 보행현시 없음"))
        precondition(assess([match],plans).estimate.totalWait == nil)
        print("Missing plan, missing basis, no pedestrian phase and empty coverage remain unknown")
    }
}
