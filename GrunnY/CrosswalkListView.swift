import SwiftUI

struct CrosswalkListView: View {
    let matches: [CrosswalkMatch]
    let dataAvailable: Bool
    let pace: Int
    @Binding var signalRows: [SeoulSignalRow]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("경로에서 12 m 이내에 있는 횡단보도 위치 후보입니다. 실제 횡단 여부와 보행신호 방향은 아직 확인되지 않았습니다.")
                    Text("도달 시간은 페이스만 반영하며 신호 대기시간은 포함하지 않습니다.")
                    Text("위치는 관련 서울시 자료의 좌표계를 적용한 변환 결과로, 검증 중입니다.")
                        .foregroundStyle(.secondary)
                }
                if matches.isEmpty {
                    Text(dataAvailable ? "경로 주변에서 후보를 찾지 못했습니다. 횡단보도가 없다는 뜻은 아닙니다. 서울 지역의 위치 자료만 포함합니다." : "횡단보도 위치 파일을 불러오지 못했습니다.")
                }
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    Section("\(index + 1). \(match.crosswalk.name.isEmpty ? "횡단보도" : match.crosswalk.name)") {
                        LabeledContent("출발 후 거리", value: "\(Int(match.metersFromStart.rounded())) m")
                        LabeledContent("대기 제외 도달 시간", value: arrivalText(match))
                        LabeledContent("경로와의 거리", value: "\(Int(match.offsetMeters.rounded())) m")
                        LabeledContent("보행등 설치", value: match.crosswalk.signalPresence.isEmpty ? "미확인" : match.crosswalk.signalPresence)
                        LabeledContent("시설 관리번호", value: match.crosswalk.id)
                        if let linked = SignalIntersectionCatalog.bundled?.link(for: match.crosswalk) {
                            LabeledContent("신호 교차로 후보 ID", value: linked.id)
                            Text("이름 일치, 좌표 80m 이내의 유일 후보 · 교차로·방향 대응 검증 필요")
                                .font(.caption).foregroundStyle(.secondary)
                            let direction = SignalIntersectionCatalog.bundled?.directionCandidate(
                                for: match.crosswalk, at: linked, allCrosswalks: CrosswalkCatalog.bundled?.crosswalks ?? [])
                            if let direction {
                                LabeledContent("신호 방향 추정", value: "\(direction.label) 진입 기준")
                                Text("서울시 방향 규칙과 좌표로 추정 · 현장 검증 전")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("방향을 하나로 정할 수 없어 전체 방향을 표시합니다.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            let saved = signalRows.filter { $0.intersectionID == linked.id }
                            if let observation = saved.max(by: { (Double($0.transmittedAt) ?? 0) < (Double($1.transmittedAt) ?? 0) }) {
                                SignalObservationView(row: observation, direction: direction)
                            } else {
                                Text("이 교차로의 저장된 신호가 없습니다.")
                                    .foregroundStyle(.secondary)
                            }
                            NavigationLink("이 교차로 후보의 보행신호 확인") {
                                SeoulSignalView(rows: $signalRows, intersectionID: linked.id)
                            }
                            Text("도착 시 대기시간 계산 불가 · 신호 주기/운영계획과 횡단 연결 검증 필요")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(match.crosswalk.signalPresence == "무" ? "보행등 미설치 시설" : "교차로 대응 자료 부족 · 신호 연결 미확인")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("데이터 출처") {
                    Link("서울특별시 · 횡단보도 시설·위치정보", destination: URL(string: "https://data.seoul.go.kr/dataList/OA-23081/F/1/datasetView.do")!)
                    Text("2026-08-24 자료 · 공공누리 1유형 · 좌표 변환 및 경로 근접 분석")
                        .font(.caption)
                    Link("서울특별시 · 교차로 MAP 정보", destination: URL(string: "https://t-data.seoul.go.kr/dataprovide/trafficdataviewfile.do?data_id=10144")!)
                    Text("2024-11-14 파일 · 포함된 1,000개 교차로만 대조 가능 · 출처표시(BY)")
                        .font(.caption)
                }
            }
            .navigationTitle("횡단보도 후보 \(matches.count)곳")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }

    private func arrivalText(_ match: CrosswalkMatch) -> String {
        let seconds = Int((match.metersFromStart / 1_000 * Double(pace)).rounded())
        return "약 \(seconds / 60)분 \(seconds % 60)초"
    }
}
