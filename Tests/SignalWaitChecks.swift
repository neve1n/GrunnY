import Foundation

@main struct SignalWaitChecks {
    static func main() {
        let origin = Date(timeIntervalSince1970: 1_000_000)
        func timing(_ start: Double, _ end: Double, until: Double = 10_000) -> PedestrianTiming {
            .init(anchor: origin, cycle: 60, walkWindows: [.init(start: start, end: end)],
                  validFrom: origin.addingTimeInterval(-100), validUntil: origin.addingTimeInterval(until))
        }
        let signal = timing(10, 20)
        precondition(signal.wait(at: origin) == 10)
        precondition(signal.wait(at: origin.addingTimeInterval(10)) == 0)
        precondition(signal.wait(at: origin.addingTimeInterval(19.9)) == 0)
        precondition(signal.wait(at: origin.addingTimeInterval(20)) == 50)
        precondition(signal.wait(at: origin.addingTimeInterval(-1)) == 11)
        precondition(timing(10,20,until:10).wait(at:origin) == nil) // next plan boundary
        precondition(signal.wait(at:origin.addingTimeInterval(-101)) == nil)
        let invalid = PedestrianTiming(anchor:origin,cycle:60,walkWindows:[.init(start:10,end:30),.init(start:20,end:40)],validFrom:origin,validUntil:origin.addingTimeInterval(100))
        precondition(invalid.wait(at:origin) == nil)
        let wrapped = PedestrianTiming(anchor:origin,cycle:60,walkWindows:[.init(start:0,end:5),.init(start:50,end:60)],validFrom:origin,validUntil:origin.addingTimeInterval(1000))
        precondition(wrapped.wait(at:origin.addingTimeInterval(59)) == 0)
        precondition(wrapped.wait(at:origin.addingTimeInterval(5)) == 45)
        func crossing(_ id:String, _ meters:Double, _ t:PedestrianTiming?) -> SignalWaitEstimator.Crossing {
            .init(id:id,metersFromStart:meters,timing:t,unavailableReason:nil)
        }
        // At 300sec/km: A at 30 sec -> 20 sec wait; B ETA becomes 80, not 60 -> 50 sec wait.
        let result = SignalWaitEstimator.evaluate(distance:1000,pace:300,departure:origin,
            crossings:[crossing("B",200,timing(10,20)),crossing("A",100,timing(50,60))],coverageVerified:true)
        precondition(result.stops.map(\.id) == ["A","B"])
        precondition(result.stops[0].wait == 20 && result.stops[1].wait == 50)
        precondition(result.stops[1].arrival == origin.addingTimeInterval(80))
        precondition(result.totalWait == 70 && result.finish == origin.addingTimeInterval(370))
        let unknown = SignalWaitEstimator.evaluate(distance:1000,pace:300,departure:origin,
            crossings:[crossing("A",100,nil),crossing("B",200,signal)],coverageVerified:true)
        precondition(unknown.totalWait == nil && unknown.finish == nil && unknown.stops[1].arrival == nil)
        let emptyUnknown = SignalWaitEstimator.evaluate(distance:1000,pace:300,departure:origin,crossings:[],coverageVerified:false)
        precondition(emptyUnknown.totalWait == nil) // zero candidates is not zero signals
        let incompleteCoverage = SignalWaitEstimator.evaluate(distance:1000,pace:300,departure:origin,
            crossings:[crossing("A",100,signal)],coverageVerified:false)
        precondition(incompleteCoverage.stops.count == 1)
        precondition(incompleteCoverage.stops[0].arrival == nil && incompleteCoverage.stops[0].wait == nil)
        precondition(incompleteCoverage.totalWait == nil && incompleteCoverage.finish == nil)
        let emptyKnown = SignalWaitEstimator.evaluate(distance:1000,pace:300,departure:origin,crossings:[],coverageVerified:true)
        precondition(emptyKnown.totalWait == 0)
        let badDistance = SignalWaitEstimator.evaluate(distance:100,pace:300,departure:origin,crossings:[crossing("A",101,signal)],coverageVerified:true)
        precondition(badDistance.totalWait == nil)
        let duplicate = SignalWaitEstimator.evaluate(distance:1000,pace:300,departure:origin,crossings:[crossing("A",100,signal),crossing("A",200,signal)],coverageVerified:true)
        precondition(duplicate.totalWait == nil)
        precondition(SignalWaitEstimator.bestIndex(estimates:[result,unknown],distances:[1000,1000],target:1000) == nil)
        precondition(SignalWaitEstimator.bestIndex(estimates:[result,emptyKnown],distances:[1000,1010],target:1000) == 1)
        precondition(SignalWaitEstimator.bestIndex(estimates:[emptyKnown,emptyKnown],distances:[1100,1001],target:1000) == 1)
        // The more distant candidate must win if its actual computed wait is lower.
        let shorterWait = SignalWaitEstimator.evaluate(distance:1100,pace:300,departure:origin,
            crossings:[crossing("C",100,timing(40,50))],coverageVerified:true)
        precondition(shorterWait.totalWait == 10)
        precondition(SignalWaitEstimator.bestIndex(estimates:[result,shorterWait],distances:[1000,1100],target:1000) == 1)
        // A partial/error result cannot be presented as a zero-wait recommendation.
        let inconsistent = SignalRouteEstimate(stops:result.stops,totalWait:0,finish:result.finish,unavailableReason:nil)
        precondition(SignalWaitEstimator.bestIndex(estimates:[inconsistent,shorterWait],distances:[1000,1100],target:1000) == nil)
        let missingFinish = SignalRouteEstimate(stops:[],totalWait:0,finish:nil,unavailableReason:nil)
        precondition(SignalWaitEstimator.bestIndex(estimates:[missingFinish],distances:[1000],target:1000) == nil)
        let cycle = StatisticalSignalCycle(red: 60, cycle: 90, validFrom: origin, validUntil: origin.addingTimeInterval(1000))
        precondition(cycle.averageWait(at: origin) == 20)
        precondition(cycle.averageWait(at: origin.addingTimeInterval(950)) == nil)
        precondition(StatisticalSignalCycle(red: 90, cycle: 90, validFrom: origin, validUntil: origin.addingTimeInterval(1000)).averageWait(at: origin) == nil)
        precondition(StatisticalSignalCycle(red: .nan, cycle: 90, validFrom: origin, validUntil: origin.addingTimeInterval(1000)).averageWait(at: origin) == nil)
        let visits = [crossing("A-1",100,nil), crossing("A-2",200,nil)]
        let average = SignalWaitEstimator.evaluateAverage(distance:1000,pace:300,departure:origin,
            crossings:visits,cycles:["A-1":cycle,"A-2":cycle],coverageVerified:true)
        precondition(average.method == .statisticalAverage && average.totalWait == 40)
        precondition(average.stops[1].arrival == origin.addingTimeInterval(80))
        let averageShorter = SignalWaitEstimator.evaluateAverage(distance:1010,pace:300,departure:origin,
            crossings:[visits[0]],cycles:["A-1":cycle],coverageVerified:true)
        precondition(SignalWaitEstimator.bestIndex(estimates:[average,averageShorter],distances:[1000,1010],target:1000) == 1)
        precondition(SignalWaitEstimator.bestIndex(estimates:[average,shorterWait],distances:[1000,1100],target:1000) == nil)
        precondition(SignalWaitEstimator.evaluateAverage(distance:1000,pace:300,departure:origin,
            crossings:visits,cycles:["A-1":cycle],coverageVerified:true).totalWait == nil)
        precondition(SignalWaitEstimator.evaluateAverage(distance:1000,pace:300,departure:origin,
            crossings:visits,cycles:["A-1":cycle,"A-2":cycle],coverageVerified:false).totalWait == nil)
        print("Arrival-time and statistical average waits, missing data, expiry and ranking passed")
    }
}
