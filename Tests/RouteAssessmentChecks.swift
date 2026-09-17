import Foundation

@main struct RouteAssessmentChecks {
    static func main() {
        let crossing = Crosswalk(id:"fixture",district:"",intersectionID:"different-system",name:"시청",signalPresence:"유",latitude:37.56,longitude:126.97)
        let match = CrosswalkMatch(crosswalk:crossing,metersFromStart:100,offsetMeters:1,visit:0)
        func assess(_ matches:[CrosswalkMatch] = [match], _ plans:SeoulPlanCollection? = nil) -> RouteSignalAssessment {
            .make(id:UUID(),distance:1000,matches:matches,pace:300,departure:Date(),plans:plans)
        }
        precondition(assess().estimate.totalWait == 15)
        precondition(assess().estimate.assumptionNote!.contains("120"))
        precondition(assess([]).estimate.totalWait == 0)
        var plans = SeoulPlanCollection(query:"시청",fetchedAt:Date(),tables:[.operation:[],.weekday:[],.holiday:[],.reservation:[]])
        precondition(assess([match],plans).estimate.totalWait == 15)
        plans.basis = SeoulPhaseBasis(fetchedAt:Date(),intersections:[["REGION_CD":"L01","INT_NO":"2904","INT_NM":"시청"]],configurations:[["REGION_CD":"L01","INT_NO":"2904","MAP_NO":"0","A_RING_1_PHASE_CONF_CD":"S170350"]])
        precondition(assess([match],plans).estimate.assumptionNote!.contains("120"))
        precondition(assess([match],plans).estimate.totalWait == 15)
        // Live remaining time never replaces the explicitly assumed fallback cycle.
        let now = Date()
        let green = SeoulSignalRow(id:"fixture",intersectionID:"fixture",transmittedAt:String(now.timeIntervalSince1970 * 1000),
            fields:[],pedestrianSignals:[.init(direction:.north,state:"protected-Movement-Allowed",remainingRaw:"10")])
        let snapshotResult = RouteSignalAssessment.make(id:UUID(),distance:1000,matches:[match],pace:300,
            departure:now,plans:plans,signalRows:[green])
        precondition(snapshotResult.estimate.totalWait == 15 && snapshotResult.estimate.finish != nil)
        precondition(snapshotResult.estimate.stops.allSatisfy { $0.wait == 15 })
        let cyclePlans = SeoulPlanCollection(query:"시청",fetchedAt:now,tables:[.operation:[
            ["INT_NO":"2904","INT_NM":"시청","INT_OPER_CYCLE_VAL":"120"]]])
        let modeled = assess([match],cyclePlans)
        precondition(modeled.estimate.method == .cycleHeuristic && modeled.estimate.totalWait == 15)
        let twice = CrosswalkMatch(crosswalk:crossing,metersFromStart:500,offsetMeters:1,visit:1)
        precondition(assess([match,twice],cyclePlans).estimate.totalWait == 30)
        precondition(assess([],cyclePlans).estimate.totalWait == 0)
        let ambiguous = SeoulPlanCollection(query:"시청",fetchedAt:now,tables:[.operation:[
            ["INT_NO":"1","INT_NM":"시청","INT_OPER_CYCLE_VAL":"120"],
            ["INT_NO":"2","INT_NM":"시청","INT_OPER_CYCLE_VAL":"120"]]])
        precondition(assess([match],ambiguous).estimate.totalWait == 15)
        let avgPlans = SeoulPlanCollection(query:"시청",fetchedAt:now,tables:[.operation:[
            ["INT_NO":"2904","INT_NM":"시청","INT_OPER_CYCLE_VAL":"120"],
            ["INT_NO":"2904","INT_NM":"시청","INT_OPER_CYCLE_VAL":"160"]]])
        precondition(assess([match],avgPlans).estimate.totalWait == 17.5)
        let otherPlans = SeoulPlanCollection(query:"",fetchedAt:now,tables:[.operation:[
            ["INT_NO":"1","INT_NM":"다른곳","INT_OPER_CYCLE_VAL":"80"],
            ["INT_NO":"1","INT_NM":"다른곳","INT_OPER_CYCLE_VAL":"120"],
            ["INT_NO":"2","INT_NM":"다른곳2","INT_OPER_CYCLE_VAL":"180"],
            ["INT_NO":"3","INT_NM":"오류","INT_OPER_CYCLE_VAL":"NaN"]]])
        // Equal intersection weighting: mean(100, 180) / 8 = 17.5, not row weighting.
        precondition(assess([match],otherPlans).estimate.totalWait == 17.5)
        precondition(assess([match],otherPlans).estimate.assumptionNote!.contains("평균"))
        let noSignal = Crosswalk(id:"none",district:"",intersectionID:"",name:"",signalPresence:"무",latitude:37.56,longitude:126.97)
        let excluded = CrosswalkMatch(crosswalk:noSignal,metersFromStart:200,offsetMeters:1,visit:0)
        precondition(assess([excluded],nil).estimate.totalWait == 0)
        precondition(assess([excluded],nil).estimate.stops.isEmpty)
        precondition(assess([match,excluded],otherPlans).estimate.totalWait == 17.5)
        let bad = RouteSignalAssessment.make(id:UUID(),distance: .nan,matches:[match],pace:300,departure:now,plans:nil)
        precondition(bad.estimate.totalWait == nil) // Invalid inputs are never hidden by a fallback.
        precondition(SignalWaitEstimator.bestIndex(estimates:[assess([match,twice],cyclePlans).estimate,modeled.estimate],distances:[1000,1010],target:1000) == 1)
        print("Cycle heuristic, repeated visits, ambiguous joins, missing data and recommendation passed")
    }
}
