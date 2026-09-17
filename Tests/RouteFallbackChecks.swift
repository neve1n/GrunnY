import Foundation
@main struct RouteFallbackChecks {
    static func main() {
        precondition(RouteFallbackPolicy.indices(distances: [5000], target: 5000) == [0])
        precondition(RouteFallbackPolicy.indices(distances: [6000, 4900, 5200], target: 5000) == [1, 2])
        precondition(RouteFallbackPolicy.indices(distances: [6000, 7000, 4500], target: 5000) == [2, 0])
        precondition(RouteFallbackPolicy.indices(distances: [4900, 6000], target: 5000) == [0, 1])
        precondition(RouteFallbackPolicy.indices(distances: [.nan, 0, .infinity, 5500], target: 5000) == [3])
        precondition(RouteFallbackPolicy.indices(distances: [], target: 5000).isEmpty)
        precondition(RouteFallbackPolicy.indices(distances: [5000, 5100], target: 5000, uncontrolledCounts: [2, 0]) == [1, 0])
        print("Single route, preferred tolerance, closest alternatives, invalid data and facility ranking passed")
    }
}
