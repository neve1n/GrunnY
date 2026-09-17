import SwiftUI

struct RouteComparisonView: View {
    let assessments: [RouteSignalAssessment]
    let pace: Int
    let departure: Date
    let selectedIndex: Int
    let canSelect: Bool
    let target: Double
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("목표 거리에 맞는 코스를 우선 찾고, 부족하면 가까운 거리의 대체 코스를 보여드려요. 추천 표시는 찾은 후보 중 예상 신호 대기가 가장 적은 코스예요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(assessments.enumerated()), id: \.element.id) { index, assessment in
                    Section {
                        LabeledContent("거리", value: "\((assessment.distance / 1000).formatted(.number.precision(.fractionLength(2)))) km")
                        LabeledContent("예상 시간", value: assessment.estimate.totalWait.map {
                            duration(assessment.distance / 1000 * Double(pace) + $0)
                        } ?? "확인 중")
                        LabeledContent("예상 신호 대기", value: assessment.estimate.totalWait.map(duration) ?? "확인 중")
                        if assessment.matches.isEmpty {
                            Text("확인된 횡단보도 정보가 없어 신호 대기가 반영되지 않았어요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if canSelect && index != selectedIndex {
                            Button("이 코스 보기") { select(index); dismiss() }
                                .frame(minHeight: 44)
                        }
                    } header: {
                        HStack {
                            Text("코스 \(index + 1)")
                            if index == recommendedIndex { Text("추천") }
                            Spacer()
                            if index == selectedIndex { Text("선택됨") }
                        }
                    }
                }
                Section("예상 시간 안내") {
                    Text("예상 시간에는 달리는 시간과 신호 대기가 포함돼요. 신호 대기는 빨간불이 주기의 절반이라고 가정한 추정치로, 실제와 다를 수 있어요. 주기 정보가 부족하면 평균값이나 기본값을 사용해요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("코스 비교")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }

        }
    }

    private var recommendedIndex: Int? {
        SignalWaitEstimator.bestIndex(estimates: assessments.map(\.estimate),
                                      distances: assessments.map(\.distance), target: target)
    }

    private func duration(_ seconds: Double) -> String {
        let seconds = Int(seconds.rounded())
        return "\(seconds / 60)분 \(seconds % 60)초"
    }
}
