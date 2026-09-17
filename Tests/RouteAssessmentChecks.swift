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
        // A fresh all-green response is not a verified crossing or full route coverage.
        // This regresses the liveTiming adapter that invented a repeating cycle and
        // treated any collection of non-nil timings as verified coverage.
        let now = Date()
        let green = SeoulSignalRow(id:"fixture",intersectionID:"fixture",transmittedAt:String(now.timeIntervalSince1970 * 1000),
            fields:[],pedestrianSignals:[.init(direction:.north,state:"protected-Movement-Allowed",remainingRaw:"10")])
        let snapshotResult = RouteSignalAssessment.make(id:UUID(),distance:1000,matches:[match],pace:300,
            departure:now,plans:plans,signalRows:[green])
        precondition(snapshotResult.estimate.totalWait == nil && snapshotResult.estimate.finish == nil)
        precondition(snapshotResult.estimate.stops.allSatisfy { $0.arrival == nil && $0.wait == nil })
        print("Missing plan, missing basis, no pedestrian phase and empty coverage remain unknown")
    }
}
