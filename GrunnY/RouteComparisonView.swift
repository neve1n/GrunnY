import SwiftUI

struct RouteComparisonView: View {
    let assessments: [RouteSignalAssessment]
    let pace: Int
    let departure: Date
    let selectedIndex: Int
    let canSelect: Bool
    let target: Double
    let select: (Int) -> Void
    @Binding var plans: SeoulPlanCollection?
    @Binding var signalRows: [SeoulSignalRow]
    @State private var inspectedMatches: [CrosswalkMatch] = []
    @State private var showsCrosswalks = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("계산 기준 출발", value: departure.formatted(date: .abbreviated, time: .standard))
                    Text("앞 신호에서 기다리는 시간을 이후 도착 시각에 누적합니다. 데이터가 부족한 코스의 대기시간은 0초로 취급하지 않습니다.")
                    NavigationLink("서울 운영계획·기반정보 확인") {
                        SeoulPlanView(result: $plans, departure: departure)
                    }
                    if let recommended = SignalWaitEstimator.bestIndex(estimates: assessments.map(\.estimate), distances: assessments.map(\.distance), target: target) {
                        Text("예상 신호 대기가 가장 적은 코스: \(recommended + 1)")
                        if canSelect { Button("추천 코스 보기") { select(recommended); dismiss() } }
                    } else {
                        Text("신호 기준 추천 보류 · 계산에 필요한 자료를 확인해 주세요.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(assessments.enumerated()), id: \.element.id) { index, assessment in
                    Section("코스 \(index + 1)\(index == selectedIndex ? " · 선택됨" : "")") {
                        LabeledContent("거리", value: "\((assessment.distance / 1000).formatted(.number.precision(.fractionLength(2)))) km")
                        LabeledContent("러닝 시간 (대기 제외)", value: duration(assessment.distance / 1000 * Double(pace)))
                        LabeledContent("신호등 미설치 근접 후보", value: "\(assessment.matches.filter { $0.crosswalk.signalPresence == "무" }.count)회 · 실제 횡단 미확인")
                        LabeledContent("예상 신호 대기", value: assessment.estimate.totalWait.map(duration) ?? "계산 보류")
                        if let reason = assessment.estimate.unavailableReason {
                            Text(reason).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if assessment.matches.isEmpty {
                            Text("횡단보도 후보가 없습니다. 자료 미포함 지역 또는 누락 가능성이 있어 신호 없는 코스로 판정하지 않습니다.")
                        }
                        if !assessment.matches.isEmpty {
                            Button("횡단보도·실시간 신호 자료 확인") {
                                inspectedMatches = assessment.matches
                                showsCrosswalks = true
                            }
                        }
                        ForEach(Array(assessment.matches.enumerated()), id: \.element.id) { number, match in
                            DisclosureGroup("\(number + 1). \(match.crosswalk.name.isEmpty ? "횡단보도 후보" : match.crosswalk.name)") {
                                LabeledContent("출발 후 거리", value: "\(Int(match.metersFromStart.rounded())) m")
                                LabeledContent("대기 제외 도달", value: duration(match.metersFromStart / 1000 * Double(pace)))
                                Text(assessment.reasons[match.id] ?? "데이터 확인 필요")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if canSelect && index != selectedIndex {
                            Button("이 코스 보기") { select(index); dismiss() }
                        }
                    }
                }
                Section {
                    Text("모든 후보의 횡단 구간과 신호계획이 검증되어야 총 대기시간으로 추천할 수 있습니다. 현재 선택은 자료를 비교할 수 있으면 신호등 미설치 횡단보도 근접 횟수를 우선하고, 그다음 목표 거리 차이를 비교합니다. 근접은 실제 횡단을 뜻하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("코스별 신호 분석")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .sheet(isPresented: $showsCrosswalks) {
                CrosswalkListView(matches: inspectedMatches, dataAvailable: CrosswalkCatalog.bundled != nil,
                                  pace: pace, signalRows: $signalRows)
            }
        }
    }

    private func duration(_ seconds: Double) -> String {
        let seconds = Int(seconds.rounded())
        return "\(seconds / 60)분 \(seconds % 60)초"
    }
}
