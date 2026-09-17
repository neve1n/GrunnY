import MapKit
import Observation

/// Follows the selected walking route; it never invents an instruction or reroutes.
@MainActor @Observable
final class RunGuidance {
    struct Step {
        let coordinates: [CLLocationCoordinate2D]
        let instruction: String
    }
    private struct Segment {
        let a: MKMapPoint
        let b: MKMapPoint
        let start: Double
        let length: Double
    }
    private struct Instruction {
        let meters: Double
        let text: String
    }
    private(set) var title = "현재 위치 확인 중"
    private(set) var subtitle = "GPS 위치를 확인하면 안내를 시작해요"
    private(set) var symbol = "location"
    private var segments: [Segment] = []
    private var instructions: [Instruction] = []
    private var total = 0.0
    private var progress = 0.0
    private var previousDate: Date?
    private var spoken: Set<String> = []
    private(set) var arrived = false
    private(set) var offRoute = OffRouteAnnouncements()
    private var arrivalFixes = 0
    private var leftOrigin = false
    private var lastOnRouteTravel = 0.0
    var emit: ((String) -> Void)?
    var cancelDirections: (() -> Void)?
    var guidanceEnded: Bool { offRoute.disabled }

    func configure(routes: [MKRoute]) {
        configure(steps: routes.flatMap { route in
            let steps = route.steps.filter { $0.distance > 0 && $0.polyline.pointCount >= 2 }
            if steps.isEmpty {
                return [Step(coordinates: (0..<route.polyline.pointCount).map { route.polyline.points()[$0].coordinate }, instruction: "")]
            }
            return steps.map { step in
                Step(coordinates: (0..<step.polyline.pointCount).map { step.polyline.points()[$0].coordinate },
                     instruction: step.instructions)
            }
        })
    }

    func configure(steps: [Step]) {
        segments = []; instructions = []; total = 0; progress = 0
        previousDate = nil; spoken = []
        arrived = false; offRoute = OffRouteAnnouncements(); arrivalFixes = 0
        leftOrigin = false; lastOnRouteTravel = 0
        title = "현재 위치 확인 중"
        subtitle = "GPS 위치를 확인하면 안내를 시작해요"
        symbol = "location"
        for step in steps {
            let text = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { instructions.append(.init(meters: total, text: text)) }
            for (a, b) in zip(step.coordinates, step.coordinates.dropFirst()) {
                let first = MKMapPoint(a), second = MKMapPoint(b)
                let length = first.distance(to: second)
                guard length.isFinite, length > 0 else { continue }
                segments.append(.init(a: first, b: second, start: total, length: length))
                total += length
            }
        }
    }

    func update(location: CLLocation?, now: Date = .now, speak: Bool = true, traveled: Double = 0) {
        guard !segments.isEmpty else {
            show("길 안내 정보가 없어요", "카드를 눌러 지도에서 코스를 확인해 주세요", "map")
            return
        }
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35,
              abs(now.timeIntervalSince(location.timestamp)) <= 15 else {
            show("현재 위치 확인 중", "GPS 위치를 확인하면 안내를 이어갈게요", "location")
            return
        }
        if let previousDate, location.timestamp <= previousDate { return }
        let elapsed = previousDate.map { max(0, location.timestamp.timeIntervalSince($0)) } ?? 0
        // Restrict the search around previous progress to avoid jumping to the end
        // at a loop's shared start/finish or a later self-intersection.
        let limit = previousDate == nil ? 80 : max(min(150, max(60, elapsed * 8)),
            offRoute.isOffRoute ? max(0, traveled - lastOnRouteTravel) * 1.5 : 0)
        let p = MKMapPoint(location.coordinate)
        var best: (meters: Double, offset: Double)?
        for segment in segments {
            guard segment.start <= progress + limit,
                  segment.start + segment.length >= progress - 25 else { continue }
            let dx = segment.b.x - segment.a.x, dy = segment.b.y - segment.a.y
            let t = max(0, min(1, ((p.x - segment.a.x) * dx + (p.y - segment.a.y) * dy) / (dx * dx + dy * dy)))
            let meters = segment.start + t * segment.length
            guard meters >= progress - 25, meters <= progress + limit else { continue }
            let offset = p.distance(to: MKMapPoint(x: segment.a.x + t * dx, y: segment.a.y + t * dy))
            if best == nil || offset < best!.offset - 1
                || (abs(offset - best!.offset) <= 1 && abs(meters - progress) < abs(best!.meters - progress)) {
                best = (meters, offset)
            }
        }
        previousDate = location.timestamp
        if let origin = segments.first?.a, p.distance(to: origin) > 50 { leftOrigin = true }
        let nearFinish = segments.last.map { p.distance(to: $0.b) <= 20 } ?? false
        let alongEnd = best.map { total - $0.meters <= 20 && $0.offset <= 30 } ?? false
        let completedDistance = progress >= total * 0.85 || (offRoute.disabled && traveled >= total * 0.9)
        if leftOrigin && completedDistance && nearFinish && (alongEnd || offRoute.disabled) {
            arrivalFixes += 1
        } else { arrivalFixes = 0 }
        if arrivalFixes >= 3 {
            arrived = true
            show("목적지에 도착했어요", "러닝 기록을 확인해 보세요", "flag.checkered")
            return
        }
        let outside = best == nil || best!.offset > 40
        if let message = offRoute.update(outside: outside, at: location.timestamp), speak {
            emit?(message)
        }
        if offRoute.disabled {
            show("경로 안내를 종료했어요", "러닝 기록은 계속되고 있어요", "map")
            return
        }
        guard let best, !outside else {
            show("코스 위치를 확인해 주세요", "카드를 눌러 지도에서 경로를 확인해 주세요", "map")
            return
        }
        progress = max(progress, best.meters)
        lastOnRouteTravel = traveled
        let next = instructions.indices.first { instructions[$0].meters > 0 && instructions[$0].meters >= progress - 8 }
        let index = next
        guard let index else {
            show("경로를 따라 달려 주세요", "목적지까지 약 \(Int(max(0, total - progress).rounded()))m 남았어요", "location")
            return
        }
        let instruction = instructions[index]
        let distance = max(0, instruction.meters - progress)
        let action = Self.action(instruction.text)
        if let next, distance > 15 {
            let meters = max(10, Int((distance / 10).rounded()) * 10)
            title = "\(meters)m 앞에서 \(action.text)"
            if speak && distance <= 55 {
                announce(Self.voiceInstruction(instruction.text, meters: meters), key: "\(next)-turn")
            }
        } else {
            title = action.text
            if speak { announce(Self.voiceInstruction(instruction.text, meters: 0), key: "\(index)-turn") }
        }
        subtitle = "길은 계속 음성으로 안내할게요"
        symbol = action.symbol
    }

    func checkFreshness(now: Date = .now) {
        guard !arrived, !offRoute.disabled,
              previousDate == nil || now.timeIntervalSince(previousDate!) > 15 else { return }
        arrivalFixes = 0
        show("현재 위치 확인 중", "GPS 위치를 확인하면 안내를 이어갈게요", "location")
    }

    static func action(_ instruction: String) -> (text: String, symbol: String) {
        let text = instruction.lowercased()
        if text.contains("유턴") || text.contains("u-turn") { return ("유턴", "arrow.uturn.backward") }
        if text.contains("좌회전") || text.contains("왼쪽") || text.contains("turn left") { return ("왼쪽으로", "arrow.turn.up.left") }
        if text.contains("우회전") || text.contains("오른쪽") || text.contains("turn right") { return ("오른쪽으로", "arrow.turn.up.right") }
        return (instruction, "location")
    }

    private func show(_ text: String, _ detail: String, _ icon: String) {
        title = text; subtitle = detail; symbol = icon
        cancelDirections?()
    }

    static func voiceInstruction(_ instruction: String, meters: Int) -> String {
        let action = action(instruction)
        switch action.symbol {
        case "arrow.turn.up.left": return meters > 0 ? "\(meters)미터 앞에서 왼쪽으로 가세요." : "왼쪽으로 가세요."
        case "arrow.turn.up.right": return meters > 0 ? "\(meters)미터 앞에서 오른쪽으로 가세요." : "오른쪽으로 가세요."
        case "arrow.uturn.backward": return "앞에서 돌아 반대 방향으로 달리세요."
        default:
            let lower = instruction.lowercased()
            if lower.contains("직진") || lower.contains("straight") { return "그대로 직진하세요." }
            return instruction
        }
    }

    private func announce(_ text: String, key: String) {
        guard spoken.insert(key).inserted else { return }
        emit?(text)
    }
}
