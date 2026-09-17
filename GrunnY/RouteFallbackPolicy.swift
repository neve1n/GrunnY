import Foundation

/// Only ranks actual connected walking loops returned by the map service.
enum RouteFallbackPolicy {
    static func indices(distances: [Double], target: Double, uncontrolledCounts: [Int]? = nil) -> [Int] {
        guard target.isFinite, target > 0 else { return [] }
        let counts = uncontrolledCounts?.count == distances.count ? uncontrolledCounts : nil
        return Array(distances.indices.filter { distances[$0].isFinite && distances[$0] > 0 }.sorted { a, b in
            let left = abs(distances[a] - target) / target
            let right = abs(distances[b] - target) / target
            let leftFits = left <= 0.05, rightFits = right <= 0.05
            if leftFits != rightFits { return leftFits }
            if leftFits, let counts, counts[a] != counts[b] { return counts[a] < counts[b] }
            if left != right { return left < right }
            return a < b
        }.prefix(2))
    }
}
