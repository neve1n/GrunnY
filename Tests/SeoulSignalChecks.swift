import Foundation

@main struct SeoulSignalChecks {
    static func main() throws {
        // Fixtures validate parsing only; these are not live signal observations.
        let data = Data("""
        [{"itstId":1537,"trsmUtcTime":1234567890000,"ntPdsgStatNm":"stop-And-Remain","ntPdsgRmdrCs":0,"etPdsgRmdrCs":null,"stStsgStatNm":"vehicle-only"},
         {"itstId":"2","etPdsgRmdrCs":"125","wtPdsgStatNm":""},
         {"itstId":"3","ntPdsgRmdrCs":true}]
        """.utf8)
        let rows = try SeoulSignalRow.parse(data)
        precondition(rows.count == 2)
        precondition(rows[0].fields.count == 2)
        precondition(rows[0].fields[1].value == "0")
        precondition(rows[1].fields[0].value == "125")
        let empty = try SeoulSignalRow.parse(Data("[]".utf8))
        precondition(empty.isEmpty)
        do {
            _ = try SeoulSignalRow.parse(Data("{\"error\":\"unauthorized\"}".utf8))
            fatalError("Error envelope must not become successful empty data")
        } catch { }
        let url = SeoulSignalRow.requestURL(key: "test+key&?=", intersection: "1537")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(items.first { $0.name == "apiKey" }?.value == "test+key&?=")
        precondition(items.first { $0.name == "itstId" }?.value == "1537")
        print("Seoul signal parser and request checks passed")
    }
}
