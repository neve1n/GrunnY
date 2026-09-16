import Foundation

@main struct SignalInterpretationChecks {
    static func main() throws {
        // Official figure: crossing west/north/east/south -> API nt/et/st/wt.
        let cases: [(Double, PedestrianDirection)] = [(270,.north),(0,.east),(90,.south),(180,.west),
            (315,.northeast),(45,.southeast),(135,.southwest),(225,.northwest)]
        for (bearing, expected) in cases {
            precondition(PedestrianDirection.fromCrosswalkBearing(bearing) == expected)
        }
        precondition(PedestrianDirection.fromCrosswalkBearing(297.5) == nil)
        precondition(PedestrianDirection.fromCrosswalkBearing(.nan) == nil)
        func remaining(_ value: String?) -> Double? {
            PedestrianObservation(direction: .north, state: nil, remainingRaw: value).remainingSeconds
        }
        precondition(remaining("125") == 12.5)
        precondition(remaining("0") == 0)
        for value in [nil,"-1","NaN","Infinity","36001","invalid"] as [String?] {
            precondition(remaining(value) == nil)
        }
        let row = try SeoulSignalRow.parse(Data("""
        [{"itstId":"1","trsmUtcTime":1789109815624,"ntPdsgStatNm":"stop-And-Remain","ntPdsgRmdrCs":125}]
        """.utf8))[0]
        precondition(row.observedAt!.timeIntervalSince1970 == 1789109815.624)
        precondition(row.pedestrianSignals.first { $0.direction == .north }!.remainingSeconds == 12.5)
        precondition(row.freshnessText(at: row.observedAt!.addingTimeInterval(31)).contains("30초 이상"))
        precondition(row.freshnessText(at: row.observedAt!.addingTimeInterval(-6)).contains("미래"))
        let intersection = SignalIntersection(id: "1", name: "test", latitude: 37.5665, longitude: 126.978)
        let catalog = SignalIntersectionCatalog(intersections: [intersection])
        let crossing = Crosswalk(id: "c1", district: "", intersectionID: "other", name: "test", signalPresence: "유", latitude: 37.5665, longitude: 126.9777)
        precondition(catalog.directionCandidate(for: crossing, at: intersection, allCrosswalks: [crossing]) == .north)
        let divided = Crosswalk(id: "c2", district: "", intersectionID: "other", name: "test", signalPresence: "유", latitude: 37.5665, longitude: 126.9776)
        precondition(catalog.directionCandidate(for: crossing, at: intersection, allCrosswalks: [crossing,divided]) == nil)
        print("Signal direction, units, freshness and ambiguity checks passed")
    }
}
