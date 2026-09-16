import MapKit

@main struct CrosswalkChecks {
    static func main() throws {
        let a = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        let b = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9800)
        func crossing(_ id: String, lat: Double = 37.5665, lon: Double) -> Crosswalk {
            Crosswalk(id: id, district: "fixture", intersectionID: "fixture", name: "fixture", signalPresence: "유", latitude: lat, longitude: lon)
        }
        let center = crossing("center", lon: 126.979)
        let far = crossing("far", lat: 37.5675, lon: 126.979)
        let early = crossing("early", lon: 126.9783)
        let matches = CrosswalkMatcher.matches(paths: [[a, a, b]], crosswalks: [center, far, early])
        precondition(matches.map { $0.crosswalk.id } == ["early", "center"])
        precondition(matches[1].metersFromStart > 80 && matches[1].metersFromStart < 100)
        precondition(matches[1].offsetMeters < 1)
        let repeated = CrosswalkMatcher.matches(paths: [[a,b,a]], crosswalks: [center])
        precondition(repeated.count == 2 && repeated[0].id != repeated[1].id)
        let nearA = CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude + 0.0001)
        let nearB = CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude - 0.0001)
        precondition(CrosswalkMatcher.matches(paths: [[a,nearA],[nearB,b]], crosswalks: [center]).isEmpty)
        precondition(CrosswalkMatcher.matches(paths: [], crosswalks: [center]).isEmpty)
        let data = try Data(contentsOf: URL(fileURLWithPath: "GrunnY/Resources/SeoulCrosswalks.json"))
        let catalog = try JSONDecoder().decode(CrosswalkCatalog.self, from: data)
        precondition(catalog.crosswalks.count == 21775)
        precondition(Set(catalog.crosswalks.map(\.id)).count == catalog.crosswalks.count)
        let start = Date()
        _ = CrosswalkMatcher.matches(paths: [[a,b,a]], crosswalks: catalog.crosswalks)
        print("Crosswalk checks passed. Full catalog scan:", Date().timeIntervalSince(start), "seconds")
    }
}
