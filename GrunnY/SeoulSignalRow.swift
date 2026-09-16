import Foundation
import CoreFoundation

struct SeoulSignalRow: Identifiable {
    let id: String
    let fetchedAt = Date()
    let intersectionID: String
    let transmittedAt: String
    let fields: [Field]
    let pedestrianSignals: [PedestrianObservation]

    struct Field {
        let name: String
        let value: String
    }

    static func requestURL(key: String, intersection: String) -> URL {
        var parts = URLComponents(string: "https://t-data.seoul.go.kr/apig/apiman-gateway/tapi/v2xSignalPhaseTimingFusionInformation/1.0")!
        parts.queryItems = [
            URLQueryItem(name: "apiKey", value: key),
            URLQueryItem(name: "type", value: "json"),
            URLQueryItem(name: "pageNo", value: "1"),
            URLQueryItem(name: "numOfRows", value: "10")
        ]
        if !intersection.isEmpty { parts.queryItems?.append(URLQueryItem(name: "itstId", value: intersection)) }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    static func parse(_ data: Data) throws -> [Self] {
        // Reject error objects and unknown response envelopes rather than treating them as no data.
        guard let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CocoaError(.coderReadCorrupt)
        }
        let directions = [("nt", "북"), ("ne", "북동"), ("et", "동"), ("se", "남동"),
                          ("st", "남"), ("sw", "남서"), ("wt", "서"), ("nw", "북서")]
        return records.enumerated().compactMap { index, record in
            guard let intersection = scalar(record["itstId"]) else { return nil }
            var fields: [Field] = []
            var observations: [PedestrianObservation] = []
            for (prefix, label) in directions {
                if let value = scalar(record[prefix + "PdsgStatNm"]) {
                    fields.append(Field(name: "\(label)쪽 보행신호", value: value))
                }
                if let value = scalar(record[prefix + "PdsgRmdrCs"]) {
                    fields.append(Field(name: "\(label)쪽 잔여시간 원본", value: value))
                }
                if let direction = PedestrianDirection(rawValue: prefix) {
                    observations.append(PedestrianObservation(direction: direction,
                        state: scalar(record[prefix + "PdsgStatNm"]),
                        remainingRaw: scalar(record[prefix + "PdsgRmdrCs"])))
                }
            }
            guard !fields.isEmpty else { return nil }
            return Self(id: "\(intersection)-\(index)", intersectionID: intersection,
                        transmittedAt: scalar(record["trsmUtcTime"]) ?? "정보 없음", fields: fields,
                        pedestrianSignals: observations)
        }
    }

    private static func scalar(_ value: Any?) -> String? {
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }
}

/// API direction describes the incoming vehicle approach, not the crossing's map side.
enum PedestrianDirection: String, CaseIterable {
    case north = "nt", northeast = "ne", east = "et", southeast = "se"
    case south = "st", southwest = "sw", west = "wt", northwest = "nw"

    var label: String {
        switch self {
        case .north: "북"
        case .northeast: "북동"
        case .east: "동"
        case .southeast: "남동"
        case .south: "남"
        case .southwest: "남서"
        case .west: "서"
        case .northwest: "북서"
        }
    }

    // Diagram in T-Data download.do?id=10000. Cardinal sectors span 55 degrees,
    // diagonal sectors 35 degrees. Leave a 5 degree ambiguity margin at boundaries.
    static func fromCrosswalkBearing(_ bearing: Double, boundaryMargin: Double = 5) -> Self? {
        guard bearing.isFinite else { return nil }
        let approach = ((bearing + 90).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let centers: [(Self, Double, Double)] = [(.north, 0, 27.5), (.northeast, 45, 17.5),
            (.east, 90, 27.5), (.southeast, 135, 17.5), (.south, 180, 27.5),
            (.southwest, 225, 17.5), (.west, 270, 27.5), (.northwest, 315, 17.5)]
        return centers.first { _, center, halfWidth in
            let delta = abs(approach - center)
            return min(delta, 360 - delta) < halfWidth - boundaryMargin
        }?.0
    }
}

struct PedestrianObservation {
    let direction: PedestrianDirection
    let state: String?
    let remainingRaw: String?

    var remainingSeconds: Double? {
        // Official field explanation says 1/10 second, despite the "Cs" field name.
        // Values >= 36000 are not treated as an ordinary finite countdown.
        guard let remainingRaw, let raw = Double(remainingRaw), raw.isFinite,
              raw >= 0, raw < 36000 else { return nil }
        return raw / 10
    }
}

extension SeoulSignalRow {
    var observedAt: Date? {
        guard let milliseconds = Double(transmittedAt), milliseconds.isFinite,
              milliseconds >= 946684800000, milliseconds < 4102444800000 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    func freshnessText(at now: Date) -> String {
        guard let observedAt else { return "원본 시각을 해석할 수 없습니다." }
        let age = now.timeIntervalSince(observedAt)
        if age < -5 { return "기기 시각보다 미래인 데이터 · 시각 검증 필요" }
        if age > 30 { return "30초 이상 지난 관측값 · 현재 신호 미확인" }
        return "최근 30초 이내 관측값 · 자동 갱신 아님"
    }
}
