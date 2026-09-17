import MapKit
import Observation

struct LoopCandidate: Identifiable {
    let id = UUID()
    let legs: [MKRoute]
    var distance: CLLocationDistance { legs.reduce(0) { $0 + $1.distance } }
    let crosswalkMatches: [CrosswalkMatch]

    init(legs: [MKRoute]) {
        self.legs = legs
        crosswalkMatches = RoutePlanner.matches(for: legs)
    }
}

@MainActor
@Observable
final class RoutePlanner {
    private(set) var route: MKRoute?
    private(set) var candidates: [LoopCandidate] = []
    private(set) var selectedIndex = 0
    private(set) var targetMeters: Double?
    private(set) var destination: CLLocationCoordinate2D?
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var progress = "보행 경로 찾는 중…"
    private(set) var crosswalkMatches: [CrosswalkMatch] = []
    var crosswalkDataAvailable: Bool { CrosswalkCatalog.bundled != nil }
    private var directions: MKDirections?
    private var requestID = UUID()
    private(set) var calculatedDeparture: Date?
    private(set) var recommendedSignalRouteID: UUID?
    private(set) var routeSignalEstimates: [UUID: SignalRouteEstimate] = [:]

    var selectedSignalEstimate: SignalRouteEstimate? {
        guard let id = selectedLoop?.id else { return nil }
        return routeSignalEstimates[id]
    }

    /// Recompute and actually select the minimum-wait candidate. Unknown coverage
    /// never participates as a zero-wait route. Inputs must belong to this search.
    func applySignalAssessments(_ assessments: [RouteSignalAssessment]) {
        recommendedSignalRouteID = nil
        routeSignalEstimates = [:]
        guard !isLoading, !candidates.isEmpty,
              assessments.count == candidates.count,
              Set(assessments.map(\.id)).count == assessments.count,
              Set(assessments.map(\.id)) == Set(candidates.map(\.id)) else { return }
        let ordered = candidates.compactMap { candidate in
            assessments.first { $0.id == candidate.id && $0.distance == candidate.distance }
        }
        guard ordered.count == candidates.count else { return }
        routeSignalEstimates = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0.estimate) })
        guard let targetMeters,
              let index = SignalWaitEstimator.bestIndex(estimates: ordered.map(\.estimate),
                                                        distances: ordered.map(\.distance), target: targetMeters) else { return }
        recommendedSignalRouteID = candidates[index].id
        selectCandidate(index)
    }

    var selectedLoop: LoopCandidate? { candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil }
    var displayedLegs: [MKRoute] { selectedLoop?.legs ?? route.map { [$0] } ?? [] }
    var distance: Double { displayedLegs.reduce(0) { $0 + $1.distance } }
    var bounds: MKMapRect? {
        guard let first = displayedLegs.first else { return nil }
        return displayedLegs.dropFirst().reduce(first.polyline.boundingMapRect) { $0.union($1.polyline.boundingMapRect) }
    }

    func selectCandidate(_ index: Int) {
        guard candidates.indices.contains(index), !isLoading else { return }
        selectedIndex = index
        matchCrosswalks()
    }

    private func matchCrosswalks() {
        crosswalkMatches = selectedLoop?.crosswalkMatches ?? Self.matches(for: displayedLegs)
    }

    static func matches(for legs: [MKRoute]) -> [CrosswalkMatch] {
        let paths = legs.map { leg in
            (0..<leg.polyline.pointCount).map { leg.polyline.points()[$0].coordinate }
        }
        return CrosswalkMatcher.matches(paths: paths, crosswalks: CrosswalkCatalog.bundled?.crosswalks ?? [])
    }

    func signalAssessments(pace: Int, plans: SeoulPlanCollection?, signalRows: [SeoulSignalRow] = []) -> [RouteSignalAssessment] {
        guard let departure = calculatedDeparture else { return [] }
        if !candidates.isEmpty {
            return candidates.map { .make(id: $0.id, distance: $0.distance, matches: $0.crosswalkMatches,
                                         pace: pace, departure: departure, plans: plans, signalRows: signalRows) }
        }
        guard route != nil else { return [] }
        return [.make(id: requestID, distance: distance, matches: crosswalkMatches, pace: pace, departure: departure, plans: plans, signalRows: signalRows)]
    }

    func clear() {
        requestID = UUID()
        directions?.cancel()
        directions = nil
        isLoading = false
        route = nil
        crosswalkMatches = []
        candidates = []
        selectedIndex = 0
        targetMeters = nil
        destination = nil
        message = nil
        calculatedDeparture = nil
        recommendedSignalRouteID = nil
        routeSignalEstimates = [:]
    }

    private func validate(_ origin: CLLocation?, departure: Date?) -> CLLocation? {
        guard let origin, origin.horizontalAccuracy >= 0,
              abs(origin.timestamp.timeIntervalSinceNow) < 120 else {
            message = "현재 위치를 다시 확인한 뒤 경로를 찾아 주세요."
            return nil
        }
        if let departure, departure <= Date() {
            message = "출발 시각이 지났습니다. 코스 조건에서 ‘지금’ 또는 미래 시각을 선택해 주세요."
            return nil
        }
        return origin
    }

    private func walkingLeg(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, departure: Date, id: UUID) async throws -> MKRoute {
        guard requestID == id else { throw CancellationError() }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .walking
        request.departureDate = departure
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        self.directions = directions
        let response = try await directions.calculate()
        guard requestID == id, !Task.isCancelled else { throw CancellationError() }
        guard let route = response.routes.first, route.distance > 0, route.polyline.pointCount >= 2 else {
            throw MKError(.directionsNotFound)
        }
        return route
    }

    func findRoute(from origin: CLLocation?, to destination: CLLocationCoordinate2D, departure: Date?) async -> MKRoute? {
        clear()
        guard let origin = validate(origin, departure: departure) else { return nil }
        guard origin.distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)) >= 20 else {
            message = "현재 위치에서 20 m 이상 떨어진 목적지를 선택해 주세요."
            return nil
        }
        self.destination = destination
        calculatedDeparture = departure ?? Date()
        let id = requestID
        progress = "보행 경로 찾는 중…"
        isLoading = true
        defer { finish(id) }
        do {
            let route = try await walkingLeg(from: origin.coordinate, to: destination, departure: calculatedDeparture!, id: id)
            self.route = route
            matchCrosswalks()
            return route
        } catch {
            if requestID == id { message = errorMessage(error) }
            return nil
        }
    }

    func findLoops(from origin: CLLocation?, targetKM: Double, pace: Int, departure: Date?,
                   selectedStart: CLLocationCoordinate2D? = nil) async {
        clear()
        let startLocation: CLLocation?
        if let selectedStart {
            guard CLLocationCoordinate2DIsValid(selectedStart) else {
                message = "선택한 출발지 좌표가 유효하지 않습니다."
                return
            }
            if let departure, departure <= Date() {
                message = "출발 시각이 지났습니다. 미래 시각을 선택해 주세요."
                return
            }
            // This is a chosen map point, not a device GPS measurement. A fixed
            // planning origin remains valid even when location access is denied.
            startLocation = CLLocation(latitude: selectedStart.latitude, longitude: selectedStart.longitude)
        } else {
            startLocation = validate(origin, departure: departure)
        }
        guard let origin = startLocation else { return }
        guard targetKM.isFinite, (0.5...42).contains(targetKM), (180...900).contains(pace) else {
            message = "코스 조건의 거리와 페이스를 확인해 주세요."
            return
        }
        let target = targetKM * 1_000
        targetMeters = target
        destination = origin.coordinate
        let id = requestID
        let startTime = departure ?? Date()
        calculatedDeparture = startTime
        isLoading = true
        defer { finish(id) }
        var found: [LoopCandidate] = []
        var serviceFailure: String?
        // 세 방향, 각 방향당 최대 한 번 거리 보정: 보행 요청은 최대 18회.
        search: for heading in 0..<3 {
            var radius = target / (2 + sqrt(2)) * 0.8
            for attempt in 0..<2 {
                guard requestID == id, !Task.isCancelled else { return }
                progress = "순환 코스 \(heading + 1)/3 확인 중\(attempt == 1 ? " · 거리 보정" : "")"
                let a = waypoint(from: origin.coordinate, meters: radius, bearing: Double(heading) * 120)
                let b = waypoint(from: origin.coordinate, meters: radius, bearing: Double(heading) * 120 + 90)
                let points = [origin.coordinate, a, b, origin.coordinate]
                var legs: [MKRoute] = []
                var eta = startTime
                do {
                    for legIndex in 0..<3 {
                        try await Task.sleep(for: .milliseconds(350))
                        let leg = try await walkingLeg(from: points[legIndex], to: points[legIndex + 1], departure: eta, id: id)
                        legs.append(leg)
                        eta.addTimeInterval(leg.distance / 1_000 * Double(pace))
                    }
                    let candidate = LoopCandidate(legs: legs)
                    let difference = abs(candidate.distance - target) / target
                    if difference <= 0.15, isConnectedLoop(legs, origin: origin.coordinate), hasLoopArea(legs, distance: candidate.distance) {
                        found.append(candidate)
                        break
                    }
                    radius *= min(1.5, max(0.5, target / candidate.distance))
                } catch {
                    guard requestID == id, !Task.isCancelled else { return }
                    if let mapError = error as? MKError, mapError.code == .directionsNotFound {
                        break // 해당 방향을 포기하고 다음 방향 탐색
                    }
                    serviceFailure = errorMessage(error)
                    break search // 네트워크/호출 제한 오류에는 요청을 반복하지 않는다.
                }
            }
        }
        guard requestID == id else { return }
        // Compare observed facilities only when every route has interpretable matches.
        // Empty/missing coverage must never win by being counted as zero hazards.
        let canCompareFacilities = found.allSatisfy {
            !$0.crosswalkMatches.isEmpty && $0.crosswalkMatches.allSatisfy {
                ["유", "무"].contains($0.crosswalk.signalPresence)
            }
        }
        candidates = found.sorted {
            if canCompareFacilities {
                let left = $0.crosswalkMatches.filter { $0.crosswalk.signalPresence == "무" }.count
                let right = $1.crosswalkMatches.filter { $0.crosswalk.signalPresence == "무" }.count
                if left != right { return left < right }
            }
            return abs($0.distance - target) < abs($1.distance - target)
        }
        matchCrosswalks()
        if candidates.isEmpty {
            message = serviceFailure ?? "목표 거리 ±15% 이내의 연결된 순환 코스를 찾지 못했습니다. 목표 거리나 출발 위치를 바꿔 주세요."
        } else if let serviceFailure {
            message = "일부 후보만 확인했습니다. \(serviceFailure)"
        }
    }

    private func finish(_ id: UUID) {
        guard requestID == id else { return }
        isLoading = false
        directions = nil
    }

    private func errorMessage(_ error: Error) -> String {
        if let mapError = error as? MKError, mapError.code == .directionsNotFound {
            return "이 지역 또는 구간에서 보행 경로를 찾지 못했습니다. 다른 위치를 선택해 주세요."
        }
        return "경로 서비스 요청에 실패했습니다. 네트워크를 확인하거나 잠시 후 다시 시도해 주세요."
    }

    private func waypoint(from origin: CLLocationCoordinate2D, meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let angularDistance = meters / 6_371_000
        let heading = bearing * .pi / 180
        let lat = origin.latitude * .pi / 180
        let lon = origin.longitude * .pi / 180
        let nextLat = asin(sin(lat) * cos(angularDistance) + cos(lat) * sin(angularDistance) * cos(heading))
        let nextLon = lon + atan2(sin(heading) * sin(angularDistance) * cos(lat), cos(angularDistance) - sin(lat) * sin(nextLat))
        return CLLocationCoordinate2D(latitude: nextLat * 180 / .pi, longitude: (nextLon * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    private func isConnectedLoop(_ legs: [MKRoute], origin: CLLocationCoordinate2D) -> Bool {
        guard legs.count == 3 else { return false }
        let starts = legs.map { $0.polyline.points()[0] }
        let ends = legs.map { $0.polyline.points()[$0.polyline.pointCount - 1] }
        // 도로 스냅 오차는 허용하되 떨어진 구간을 임의의 선으로 잇지 않는다.
        return starts[0].distance(to: MKMapPoint(origin)) <= 50
            && ends[2].distance(to: MKMapPoint(origin)) <= 50
            && zip(ends, [starts[1], starts[2], starts[0]]).allSatisfy { $0.distance(to: $1) <= 20 }
    }

    private func hasLoopArea(_ legs: [MKRoute], distance: Double) -> Bool {
        // 면적이 거의 없는 단순 왕복 경로는 순환 코스 후보에서 제외한다.
        let points = legs.flatMap { leg in (0..<leg.polyline.pointCount).map { leg.polyline.points()[$0] } }
        guard let anchor = points.first else { return false }
        let scale = MKMetersPerMapPointAtLatitude(anchor.coordinate.latitude)
        var twiceArea = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            twiceArea += (a.x - anchor.x) * (b.y - anchor.y) - (b.x - anchor.x) * (a.y - anchor.y)
        }
        return abs(twiceArea) * scale * scale / 2 > distance * distance * 0.005
    }
}
