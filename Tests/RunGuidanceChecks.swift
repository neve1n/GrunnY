import Foundation
import CoreLocation

@main struct RunGuidanceChecks {
    @MainActor static func main() {
        let guide = RunGuidance()
        let a = CLLocationCoordinate2D(latitude: 37.5, longitude: 127)
        let b = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.001)
        let c = CLLocationCoordinate2D(latitude: 37.501, longitude: 127.001)
        guide.configure(steps: [
            .init(coordinates: [a, b], instruction: "직진"),
            .init(coordinates: [b, c], instruction: "좌회전"),
            .init(coordinates: [c, a], instruction: "출발지로 이동")
        ])
        let now = Date()
        func point(_ coordinate: CLLocationCoordinate2D, _ seconds: Double = 0, accuracy: Double = 5) -> CLLocation {
            CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: accuracy,
                       verticalAccuracy: 5, timestamp: now.addingTimeInterval(seconds))
        }
        guide.update(location: point(a), now: now, speak: false)
        precondition(guide.title.contains("왼쪽"), guide.title)
        precondition(!guide.title.contains("도착"))
        let first = guide.title
        let halfway = CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0005)
        guide.update(location: point(halfway, 8), now: now.addingTimeInterval(8), speak: false)
        precondition(guide.title != first && guide.title.contains("왼쪽"), guide.title)
        guide.update(location: point(c, 9), now: now.addingTimeInterval(9), speak: false)
        precondition(guide.title == "코스 위치를 확인해 주세요", guide.title)
        guide.update(location: point(halfway, 10, accuracy: 80), now: now.addingTimeInterval(10), speak: false)
        precondition(guide.title == "현재 위치 확인 중")
        guide.update(location: point(halfway), now: now.addingTimeInterval(30), speak: false)
        precondition(guide.title == "현재 위치 확인 중")
        precondition(RunGuidance.action("Turn right").symbol == "arrow.turn.up.right")
        precondition(RunGuidance.action("보행자 통로 이용").text == "보행자 통로 이용")
        guide.configure(steps: [])
        guide.update(location: point(a), now: now, speak: false)
        precondition(guide.title == "길 안내 정보가 없어요")
        guide.configure(steps: [
            .init(coordinates: [a, b], instruction: "직진"),
            .init(coordinates: [b, c], instruction: "좌회전"),
            .init(coordinates: [c, a], instruction: "출발지로 이동")
        ])
        var seconds = 0.0
        for (from, to) in [(a, b), (b, c), (c, a)] {
            for quarter in 0...4 {
                let fraction = Double(quarter) / 4
                let coordinate = CLLocationCoordinate2D(latitude: from.latitude + (to.latitude - from.latitude) * fraction,
                    longitude: from.longitude + (to.longitude - from.longitude) * fraction)
                guide.update(location: point(coordinate, seconds), now: now.addingTimeInterval(seconds), speak: false)
                seconds += 5
            }
        }
        precondition(!guide.arrived, "Require consecutive destination fixes")
        for _ in 0..<3 {
            guide.update(location: point(a, seconds), now: now.addingTimeInterval(seconds), speak: false)
            seconds += 5
        }
        precondition(guide.arrived, "Completed loop should arrive")
        precondition(RunGuidance.voiceInstruction("좌회전", meters: 50) == "50미터 앞에서 왼쪽으로 가세요.")
        precondition(RunGuidance.voiceInstruction("직진", meters: 0) == "그대로 직진하세요.")
        print("Guidance: loop start, distance, off-route jump, stale/inaccurate GPS and missing steps passed")
    }
}
