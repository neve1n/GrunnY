import Foundation

@main struct SeoulPlanChecks {
    static func main() throws {
        let denied = Data("<OpenAPI_ServiceResponse><cmmMsgHeader><returnReasonCode>20</returnReasonCode><returnAuthMsg>secret-key</returnAuthMsg></cmmMsgHeader></OpenAPI_ServiceResponse>".utf8)
        let rejection = SeoulPlanPage.responseFailure(status: 403, data: denied).errorDescription!
        precondition(rejection.contains("403") && rejection.contains("20") && !rejection.contains("secret-key"))
        let unsafe = Data("<error><resultCode>secret-key</resultCode></error>".utf8)
        precondition(!SeoulPlanPage.responseFailure(status: 403, data: unsafe).errorDescription!.contains("secret-key"))
        precondition(SeoulPlanPage.responseFailure(status: 403, data: Data("Forbidden".utf8)).errorDescription!.contains("원인은 확정할 수 없습니다"))
        let sample = """
        <PlanCrossRoadInfoService><Header><resultCode>0</resultCode><totCount>1</totCount><totPage>1</totPage><pageNo>1</pageNo></Header><PlanCROPInfo><REGION_CD>L01</REGION_CD><INT_NO>2904</INT_NO><INT_NM>시청</INT_NM><INT_OPER_CYCLE_VAL>180</INT_OPER_CYCLE_VAL><INT_OPER_OFFSET_VAL>10</INT_OPER_OFFSET_VAL></PlanCROPInfo></PlanCrossRoadInfoService>
        """
        let result = try SeoulPlanPage.decode(Data(sample.utf8))
        precondition(result.rows.count == 1 && result.rows[0]["INT_OPER_CYCLE_VAL"] == "180")
        for bad in [sample.replacingOccurrences(of: "L01", with: "L29"), sample.replacingOccurrences(of: "<resultCode>0", with: "<resultCode>30"), "<html>error</html>", sample.replacingOccurrences(of: "<totCount>1", with: "<totCount>0")] {
            do { _ = try SeoulPlanPage.decode(Data(bad.utf8)); fatalError("Must reject") } catch { }
        }
        for key in ["test+key/==", "test%2Bkey%2F%3D%3D"] {
            let url = SeoulPlanPage.url(key: key, name: "시청")
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(items.first { $0.name == "serviceKey" }?.value == "test+key/==")
            precondition(items.first { $0.name == "srchCTId" }?.value == "L01")
        }
        print("Seoul plan parser and key encoding checks passed")
    }
}
