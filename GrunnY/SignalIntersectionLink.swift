import CoreLocation
import Foundation

struct SignalIntersection: Decodable, Identifiable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
}

struct SignalIntersectionCatalog: Decodable {
    let intersections: [SignalIntersection]
    static let bundled: SignalIntersectionCatalog? = {
        guard let url = Bundle.main.url(forResource: "SeoulIntersections", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()

    // Conservative corroboration, not a provider-certified crosswalk-to-direction mapping.
    // T-GIS and T-Data IDs differ. Require one exact name match (ignoring spaces)
    // within 80 m; expose this as a candidate until direction mapping is available.
    func link(for crosswalk: Crosswalk) -> SignalIntersection? {
        guard crosswalk.signalPresence == "유" else { return nil }
        let name = crosswalk.name.filter { !$0.isWhitespace }
        guard !name.isEmpty else { return nil }
        let matches = intersections.filter {
            $0.name.filter { !$0.isWhitespace } == name
                && CLLocation(latitude: crosswalk.latitude, longitude: crosswalk.longitude)
                    .distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 80
        }
        guard matches.count == 1, let intersection = matches.first,
              CLLocation(latitude: crosswalk.latitude, longitude: crosswalk.longitude)
                .distance(from: CLLocation(latitude: intersection.latitude, longitude: intersection.longitude)) <= 80 else { return nil }
        return intersection
    }
}

extension SignalIntersectionCatalog {
    /// A geometric proposal using the provider's right-side rule, never a verified assignment.
    func directionCandidate(for crosswalk: Crosswalk, at intersection: SignalIntersection,
                            allCrosswalks: [Crosswalk]) -> PedestrianDirection? {
        guard let direction = Self.direction(crosswalk, at: intersection) else { return nil }
        let peers = allCrosswalks.filter {
            $0.signalPresence == "유" && $0.intersectionID == crosswalk.intersectionID
                && Self.direction($0, at: intersection) == direction
        }
        // Divided/parallel crossings with the same signal group need an explicit mapping.
        guard peers.count == 1, peers.first?.id == crosswalk.id else { return nil }
        return direction
    }

    private static func direction(_ crosswalk: Crosswalk, at intersection: SignalIntersection) -> PedestrianDirection? {
        let center = CLLocation(latitude: intersection.latitude, longitude: intersection.longitude)
        let point = CLLocation(latitude: crosswalk.latitude, longitude: crosswalk.longitude)
        guard (8...80).contains(center.distance(from: point)) else { return nil }
        let lat1 = intersection.latitude * .pi / 180, lat2 = crosswalk.latitude * .pi / 180
        let delta = (crosswalk.longitude - intersection.longitude) * .pi / 180
        let bearing = atan2(sin(delta) * cos(lat2), cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(delta)) * 180 / .pi
        return PedestrianDirection.fromCrosswalkBearing(bearing)
    }
}
