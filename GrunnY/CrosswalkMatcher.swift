import MapKit

struct Crosswalk: Decodable, Identifiable {
    let id: String
    let district: String
    // T-GIS identifier: must not be assumed to equal T-Data itstId.
    let intersectionID: String
    let name: String
    let signalPresence: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct CrosswalkMatch: Identifiable {
    let crosswalk: Crosswalk
    let metersFromStart: Double
    let offsetMeters: Double
    let visit: Int
    var id: String { "\(crosswalk.id)-\(visit)" }
}

struct CrosswalkCatalog: Decodable {
    let crosswalks: [Crosswalk]
    static let bundled: CrosswalkCatalog? = {
        guard let url = Bundle.main.url(forResource: "SeoulCrosswalks", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()
}

// Point proximity is a candidate, not proof that a route crosses a road.
// No invented connection between disconnected legs, and repeat visits are preserved.
enum CrosswalkMatcher {
    static let toleranceMeters = 12.0

    static func matches(paths: [[CLLocationCoordinate2D]], crosswalks: [Crosswalk]) -> [CrosswalkMatch] {
        struct Segment {
            let a: MKMapPoint
            let b: MKMapPoint
            let start: Double
            let length: Double
            let scale: Double
        }
        var segments: [Segment] = []
        var distance = 0.0
        for path in paths {
            for (first, second) in zip(path, path.dropFirst()) {
                let a = MKMapPoint(first), b = MKMapPoint(second)
                let length = a.distance(to: b)
                guard length > 0 else { continue }
                segments.append(Segment(a: a, b: b, start: distance, length: length,
                                        scale: MKMetersPerMapPointAtLatitude((first.latitude + second.latitude) / 2)))
                distance += length
            }
        }
        guard !segments.isEmpty else { return [] }
        let coordinates = paths.flatMap { $0 }
        let minLat = coordinates.map(\.latitude).min()! - 0.0002
        let maxLat = coordinates.map(\.latitude).max()! + 0.0002
        let minLon = coordinates.map(\.longitude).min()! - 0.0003
        let maxLon = coordinates.map(\.longitude).max()! + 0.0003
        var result: [CrosswalkMatch] = []
        for crossing in crosswalks where (minLat...maxLat).contains(crossing.latitude)
            && (minLon...maxLon).contains(crossing.longitude) {
            let p = MKMapPoint(crossing.coordinate)
            var hits: [(distance: Double, offset: Double)] = []
            for segment in segments {
                let padding = toleranceMeters / segment.scale
                guard p.x >= min(segment.a.x, segment.b.x) - padding,
                      p.x <= max(segment.a.x, segment.b.x) + padding,
                      p.y >= min(segment.a.y, segment.b.y) - padding,
                      p.y <= max(segment.a.y, segment.b.y) + padding else { continue }
                let dx = segment.b.x - segment.a.x, dy = segment.b.y - segment.a.y
                let t = max(0, min(1, ((p.x - segment.a.x) * dx + (p.y - segment.a.y) * dy) / (dx * dx + dy * dy)))
                let offset = hypot(p.x - segment.a.x - t * dx, p.y - segment.a.y - t * dy) * segment.scale
                guard offset <= toleranceMeters else { continue }
                hits.append((segment.start + t * segment.length, offset))
            }
            // Adjacent polyline segments can all hit the same crossing. Collapse each visit,
            // but retain later visits separated by at least 40 m along the route.
            var groups: [[(distance: Double, offset: Double)]] = []
            for hit in hits {
                if let last = groups.last?.last, hit.distance - last.distance < 40 {
                    groups[groups.count - 1].append(hit)
                } else { groups.append([hit]) }
            }
            for (visit, group) in groups.enumerated() {
                let best = group.min { $0.offset < $1.offset }!
                result.append(CrosswalkMatch(crosswalk: crossing, metersFromStart: best.distance,
                                            offsetMeters: best.offset, visit: visit))
            }
        }
        return result.sorted { $0.metersFromStart < $1.metersFromStart }
    }
}
