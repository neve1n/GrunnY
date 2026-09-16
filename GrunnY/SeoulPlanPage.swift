import Foundation

struct SeoulPlanPage {
    let rows: [[String: String]]
    let total: Int
    let pages: Int
    let page: Int

    static func url(key: String, name: String, kind: SeoulPlanKind = .operation, page: Int = 1) -> URL {
        var parts = URLComponents(string: "https://apis.data.go.kr/1320000/PlanCrossRoadInfoService/\(kind.endpoint)")!
        // Accept either encoding or decoding key copied from the portal; encode exactly once.
        let decoded = key.contains("%") ? key.removingPercentEncoding ?? key : key
        parts.queryItems = [URLQueryItem(name: "serviceKey", value: decoded),
            URLQueryItem(name: "type", value: "xml"), URLQueryItem(name: "srchCTId", value: "L01"),
            URLQueryItem(name: "srchCRNm", value: name), URLQueryItem(name: "pageNo", value: String(page)),
            URLQueryItem(name: "numOfRows", value: "100")]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    static func decode(_ data: Data, kind: SeoulPlanKind = .operation) throws -> Self {
        try decode(data, recordElement: kind.rawValue)
    }

    static func decode(_ data: Data, recordElement: String) throws -> Self {
        guard data.count <= 5_000_000 else { throw PlanFailure.invalid }
        let reader = PlanXMLReader(recordElement: recordElement)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse() else { throw PlanFailure.invalid }
        let code = reader.header["resultCode"] ?? reader.header["returnReasonCode"]
        guard let code else { throw PlanFailure.invalid }
        guard code == "0" || code == "00" else { throw PlanFailure.server(code) }
        guard let total = Int(reader.header["totCount"] ?? reader.header["totalCount"] ?? ""), total >= 0,
              let pages = Int(reader.header["totPage"] ?? ""), pages >= 0,
              let page = Int(reader.header["pageNo"] ?? ""), page >= 0,
              reader.rows.count <= total,
              total == 0 ? reader.rows.isEmpty : (!reader.rows.isEmpty && page >= 1 && page <= pages && pages >= 1) else {
            throw PlanFailure.invalid
        }
        guard reader.rows.allSatisfy({ $0["REGION_CD"] == "L01" && !($0["INT_NO"] ?? "").isEmpty }) else {
            throw PlanFailure.invalid
        }
        return Self(rows: reader.rows, total: total, pages: pages, page: page)
    }

    static func responseFailure(status: Int, data: Data) -> PlanFailure {
        // Only expose recognized provider codes, never response text or a URL containing the key.
        guard data.count <= 5_000_000 else { return .http(status) }
        let reader = PlanXMLReader(recordElement: "__no_record__")
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), let raw = reader.header["returnReasonCode"] ?? reader.header["resultCode"],
              raw.count <= 2, let number = Int(raw), [12, 20, 22, 23, 30, 31, 32].contains(number) else { return .http(status) }
        return .rejected(status, String(number))
    }
}

enum PlanFailure: LocalizedError {
    case invalid, server(String), incomplete, http(Int), rejected(Int, String)
    case countMismatch(page: Int, received: Int, accumulated: Int, declared: Int)
    var errorDescription: String? {
        switch self {
        case .countMismatch(let page, let received, let accumulated, let declared):
            "서버 건수 불일치: \(page)페이지 응답 \(received)건, 누적 \(accumulated)건, 서버 안내 총 \(declared)건입니다. 전체 수집으로 확정하지 않았습니다."
        case .invalid: "응답 형식이나 서울 지역코드를 확인하지 못했습니다."
        case .incomplete: "페이지 누락·중복·변경 또는 조회 한도 초과로 전체 수집하지 못했습니다. 교차로 이름을 구체적으로 입력해 주세요."
        case .http(let code):
            switch code {
            case 403: "서버가 접근을 거부했습니다 (HTTP 403). 이 응답만으로 원인은 확정할 수 없습니다. 해당 서비스의 활용 승인과 공공데이터포털 인증키를 확인해 주세요."
            case 429: "요청 제한 (HTTP 429). 자동 재시도하지 않습니다."
            default: "서버 요청 실패 (HTTP \(code)). 승인 및 서비스 상태를 확인해 주세요."
            }
        case .rejected(let status, let code): "HTTP \(status) · 제공기관 오류 \(code)\n\(PlanFailure.server(code).errorDescription ?? "요청 실패")"
        case .server(let code):
            switch code {
            case "22": "서버 요청 한도에 도달했습니다. 자동 재시도하지 않습니다."
            case "23": "짧은 시간의 요청 제한입니다. 자동 재시도하지 않습니다."
            case "30", "31", "32": "인증키 등록·유효기간·허용 IP를 확인해 주세요."
            case "20": "이 서비스의 활용 승인 상태를 확인해 주세요."
            case "12": "서버가 해당 서비스가 없거나 폐기되었다고 응답했습니다."
            default: "운영계획 서버가 오류를 반환했습니다. 활용 승인과 서비스 상태를 확인해 주세요."
            }
        }
    }
}

private final class PlanXMLReader: NSObject, XMLParserDelegate {
    let recordElement: String
    init(recordElement: String) { self.recordElement = recordElement }
    var header: [String: String] = [:]
    var rows: [[String: String]] = []
    private var row: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""
        if name == recordElement { row = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == recordElement {
            if let row { rows.append(row) }
            row = nil
        } else if row != nil, !value.isEmpty {
            row?[name] = value
        } else if ["resultCode", "returnReasonCode", "totCount", "totalCount", "totPage", "pageNo"].contains(name) {
            header[name] = value
        }
        text = ""
    }
}
