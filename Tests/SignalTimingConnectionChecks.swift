import Foundation

@main struct SignalTimingConnectionChecks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_789_109_815)
        let intersection = SignalIntersection(id: "1", name: "test", latitude: 37.5665, longitude: 126.978)
        let catalog = SignalIntersectionCatalog(intersections: [intersection])
        let crosswalk = Crosswalk(id: "c", district: "", intersectionID: "tgis", name: "test", signalPresence: "유", latitude: 37.5665, longitude: 126.9777)
        func row(_ state: String, _ seconds: String = "100", date: Date? = nil, id: String = "1") -> SeoulSignalRow {
            .init(id: UUID().uuidString, intersectionID: id, transmittedAt: String((date ?? now).timeIntervalSince1970 * 1000), fields: [], pedestrianSignals: [
                .init(direction: .north, state: state, remainingRaw: seconds)])
        }
        func check(_ rows: [SeoulSignalRow]) -> SignalTimingConnection {
            .inspect(crosswalk: crosswalk, rows: rows, catalog: catalog, allCrosswalks: [crosswalk], now: now)
        }
        let green = check([row("protected-Movement-Allowed")])
        precondition(green.stateEndsAt == now.addingTimeInterval(10))
        precondition(green.observedGreenWait(at: now.addingTimeInterval(5)) == 0)
        precondition(green.observedGreenWait(at: now.addingTimeInterval(8)) == nil)
        precondition(green.observedGreenWait(at: now.addingTimeInterval(-1)) == nil)
        precondition(green.observedGreenWait(at: now.addingTimeInterval(120)) == nil)
        for state in ["stop-And-Remain", "protected-clearance", "permissive-clearance", "not-protected-Movement-Allowed"] {
            precondition(check([row(state)]).observedGreenWait(at: now) == nil)
        }
        precondition(check([row("protected-Movement-Allowed", "900", date: now.addingTimeInterval(-31))]).stateEndsAt == nil)
        precondition(check([row("protected-Movement-Allowed", date: now.addingTimeInterval(1))]).stateEndsAt == nil)
        precondition(check([row("protected-Movement-Allowed", "10", date: now.addingTimeInterval(-2))]).stateEndsAt == nil)
        precondition(check([row("protected-Movement-Allowed"), row("stop-And-Remain")]).stateEndsAt == nil)
        precondition(check([row("protected-Movement-Allowed", id: "unrelated")]).stateEndsAt == nil)
        precondition(check([row("protected-Movement-Allowed", "NaN")]).stateEndsAt == nil)
        print("Timing connection: timestamps, state boundaries, stale data, conflicts and no extrapolation passed")
    }
}
