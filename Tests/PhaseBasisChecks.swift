import Foundation

@main struct PhaseBasisChecks {
    static func main() throws {
        let p = PolicePhaseCode("P090270")!
        precondition(p.isPedestrian && p.entryAngle == 90 && p.exitAngle == 270)
        precondition(PolicePhaseCode("S170350")?.isPedestrian == false)
        for invalid in ["", "P90270", "P360090", "P-10270", "X090270", "P０９０２７０", "P090270extra"] {
            precondition(PolicePhaseCode(invalid) == nil)
        }
        let xml = """
        <CrossRoadInfoResponse><Header><resultCode>0</resultCode><totPage>1</totPage><totCount>1</totCount><pageNo>1</pageNo></Header>
        <CrossRoadInfoDetail><REGION_CD>L01</REGION_CD><INT_NO>2904</INT_NO><MAP_NO>0</MAP_NO><A_RING_1_PHASE_CONF_CD>P090270</A_RING_1_PHASE_CONF_CD><A_RING_2_PHASE_CONF_CD/></CrossRoadInfoDetail></CrossRoadInfoResponse>
        """
        let page = try SeoulPlanPage.decode(Data(xml.utf8), recordElement: "CrossRoadInfoDetail")
        precondition(page.rows[0]["A_RING_1_PHASE_CONF_CD"] == "P090270")
        do { _ = try SeoulPlanPage.decode(Data(xml.utf8), recordElement: "CrossRoadInfoList"); fatalError("wrong record type") } catch { }
        let intersection = ["REGION_CD":"L01", "INT_NO":"2904"]
        let basis = SeoulPhaseBasis(fetchedAt: .now, intersections: [intersection], configurations: page.rows)
        precondition(basis.configurations(for: "2904").count == 1)
        precondition(basis.configurations(for: "9999").isEmpty)
        let ambiguous = SeoulPhaseBasis(fetchedAt: .now, intersections: [intersection, intersection], configurations: page.rows)
        precondition(ambiguous.configurations(for: "2904").isEmpty)
        for detail in [false, true] {
            let url = SeoulPhaseBasis.url(key: "a%2Bb%2Fc%3D", name: "시청", detail: detail, page: 2)
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            precondition(parts.path.hasSuffix(detail ? "getCrossRoadInfoDetail" : "getCrossRoadInfoList"))
            precondition(parts.queryItems!.first { $0.name == "serviceKey" }!.value == "a+b/c=")
            precondition(parts.queryItems!.first { $0.name == "pageNo" }!.value == "2")
            precondition(parts.queryItems!.first { $0.name == "srchCTId" }!.value == "L01")
        }
        print("Phase basis checks passed")
    }
}
