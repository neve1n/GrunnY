import SwiftUI

struct SignalObservationView: View {
    let row: SeoulSignalRow
    var direction: PedestrianDirection?

    var body: some View {
        LabeledContent("조회 시각", value: row.fetchedAt.formatted(date: .omitted, time: .standard))
        if let date = row.observedAt {
            LabeledContent("원본 관측 시각", value: date.formatted(date: .abbreviated, time: .standard))
        } else {
            LabeledContent("원본 전송 시각", value: row.transmittedAt)
        }
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(row.freshnessText(at: context.date))
                .font(.caption).foregroundStyle(.secondary)
        }
        if let direction, !row.pedestrianSignals.contains(where: {
            $0.direction == direction && ($0.state != nil || $0.remainingRaw != nil)
        }) {
            Text("추정 방향의 보행신호 값이 없습니다.")
                .foregroundStyle(.secondary)
        }
        ForEach(row.pedestrianSignals.filter {
            (direction == nil || $0.direction == direction) && ($0.state != nil || $0.remainingRaw != nil)
        }, id: \.direction) { observation in
            LabeledContent("\(observation.direction.label) 진입 기준 보행신호", value: observation.state ?? "상태 없음")
            if let seconds = observation.remainingSeconds {
                LabeledContent("관측 당시 잔여시간", value: "\(seconds.formatted(.number.precision(.fractionLength(1))))초")
            } else {
                LabeledContent("잔여시간", value: "해석 불가 / 없음")
            }
        }
        Text("관측값이며 현재 통행 가능 여부나 미래 신호를 보장하지 않습니다.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
