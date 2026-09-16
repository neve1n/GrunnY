import Foundation

@main struct SignalLinkChecks {
    static func main() throws {
        let catalog = SignalIntersectionCatalog(intersections: [.init(id: "1", name: "테스트 교차로", latitude: 37.5665, longitude: 126.978)])
        func crossing(_ id: String = "1", _ name: String = "테스트교차로", _ lat: Double = 37.5665, _ signal: String = "유") -> Crosswalk {
            .init(id: "fixture", district: "fixture", intersectionID: id, name: name, signalPresence: signal, latitude: lat, longitude: 126.978)
        }
        precondition(catalog.link(for: crossing())?.id == "1")
        precondition(catalog.link(for: crossing("2"))?.id == "1") // Different source ID namespace.
        precondition(catalog.link(for: crossing("1", "다른교차로")) == nil)
        precondition(catalog.link(for: crossing("1", "테스트교차로", 37.57)) == nil)
        precondition(catalog.link(for: crossing("1", "테스트교차로", 37.5665, "무")) == nil)
        let duplicate = SignalIntersectionCatalog(intersections: catalog.intersections + catalog.intersections)
        precondition(duplicate.link(for: crossing()) == nil)
        let decoder = JSONDecoder()
        let real = try decoder.decode(SignalIntersectionCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: "GrunnY/Resources/SeoulIntersections.json")))
        let crossings = try decoder.decode(CrosswalkCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: "GrunnY/Resources/SeoulCrosswalks.json")))
        let linked = crossings.crosswalks.filter { real.link(for: $0) != nil }
        print("Link checks passed; matched crossings:", linked.count, "intersections:", Set(linked.map(\.intersectionID)).count)
        print("Example:", linked.first?.name ?? "none", linked.first?.intersectionID ?? "none")
    }
}
