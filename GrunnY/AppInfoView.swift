import SwiftUI

enum AppPublication {
    static let website = URL(string: "https://grunny-support.wapples150.chatgpt.site")
    static let email = "seojin060504@gmail.com"
}

struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("저장한 러닝 기록") { RunHistoryView() }
                    NavigationLink("개인정보처리방침") { PrivacyPolicyView() }
                    if let website = AppPublication.website {
                        Link("지원 및 문의", destination: website)
                    }
                    Link("이메일로 문의", destination: URL(string: "mailto:\(AppPublication.email)")!)
                    Text("운영자 최서진 · \(AppPublication.email)")
                        .font(.footnote).textSelection(.enabled)
                }
                Section("코스와 신호 안내") {
                    Text("서울 내 장소를 검색해 보행 코스를 찾습니다. 신호 대기는 주변 횡단보도와 주기 가정에 따른 예상치이며, 실제 빨간불·초록불이나 절약 시간을 예측하지 않습니다.")
                    Text("주기 정보가 없으면 120초, 빨간불 비율은 50%로 가정합니다. 주변 시설 수는 실제 건너는 횡단보도 수와 다를 수 있습니다. 건널 때에는 현장의 신호와 도로 상황을 확인해 주세요.")
                }
                Section("데이터 출처") {
                    Link("서울특별시 · 횡단보도 시설·위치정보", destination: URL(string: "https://data.seoul.go.kr/dataList/OA-23081/F/1/datasetView.do")!)
                    Text("서울특별시 제공 자료를 좌표 변환·가공하여 사용합니다. 지도와 보행 경로: Apple Maps.")
                        .font(.footnote)
                }
            }
            .navigationTitle("앱 정보")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }.tint(GrunnYStyle.brand)
    }
}

struct PrivacyPolicyView: View {
    private var policy: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "개인정보 관련 문의: 최서진 · \(AppPublication.email)"
        }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let website = AppPublication.website {
                    Link("웹에서 개인정보처리방침 보기", destination: website.appendingPathComponent("privacy.html"))
                }
                Text(policy).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(20)
        }.navigationTitle("개인정보처리방침").navigationBarTitleDisplayMode(.inline)
    }
}

private struct RunHistoryView: View {
    @State private var records: [RunRecord] = []
    @State private var error: String?
    @State private var confirmsDeleteAll = false
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if records.isEmpty && error == nil {
                Text("저장한 러닝 기록이 없어요.").foregroundStyle(.secondary)
            }
            ForEach(records, id: \.id) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.startedAt, format: .dateTime.year().month().day().hour().minute())
                    Text(String(format: "%.2f km", record.distance / 1000))
                        .font(.title2.bold())
                    Text("시간 \(GrunnYStyle.elapsed(record.endedAt.timeIntervalSince(record.startedAt)))")
                    Text(record.missionComplete ? "미션 완료" : "러닝 기록")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.onDelete { offsets in
                do {
                    for index in offsets { try records[index].delete() }
                    reload()
                } catch { self.error = "기록을 삭제하지 못했어요. 다시 시도해 주세요."; reloadKeepingError() }
            }
        }
        .navigationTitle("러닝 기록")
        .toolbar {
            if !records.isEmpty || error != nil {
                Button("전체 삭제", role: .destructive) { confirmsDeleteAll = true }
            }
        }
        .confirmationDialog("모든 러닝 기록을 삭제할까요? GPS 경로도 함께 삭제되며 되돌릴 수 없어요.", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
            Button("전체 삭제", role: .destructive) {
                do { try RunRecord.deleteAll(); reload() }
                catch { self.error = "기록을 삭제하지 못했어요. 다시 시도해 주세요." }
            }
        }
        .task { reload() }
    }
    private func reload() { error = nil; reloadKeepingError() }
    private func reloadKeepingError() {
        do { records = try RunRecord.loadAll() }
        catch { self.error = "저장한 기록을 읽지 못했어요. 앱을 다시 열거나 전체 삭제할 수 있어요." }
    }
}
