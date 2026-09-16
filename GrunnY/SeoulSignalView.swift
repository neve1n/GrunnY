import SwiftUI

// A manual connection check before using the feed for route predictions.
struct SeoulSignalView: View {
    @State private var apiKey = ""
    @State private var intersectionID: String
    @State private var status = "인증키를 입력하고 연결을 확인해 주세요."
    @Binding var rows: [SeoulSignalRow]
    @State private var request: Task<Void, Never>?
    @State private var generation = UUID()
    @FocusState private var isEditing: Bool

    init(rows: Binding<[SeoulSignalRow]>, intersectionID: String = "") {
        _rows = rows
        _intersectionID = State(initialValue: intersectionID)
    }

    var body: some View {
        Form {
            Section {
                SecureField("T-Data 인증키", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isEditing)
                TextField("교차로 ID (선택)", text: $intersectionID)
                    .keyboardType(.numberPad)
                    .focused($isEditing)
            } header: {
                Text("서울 T-Data 연결")
            } footer: {
                Text("인증키는 이 화면에만 입력하세요. 파일에 저장하지 않으며 화면을 나가면 지웁니다. 교차로 ID를 비우면 첫 10건을 조회합니다.")
            }
            .disabled(request != nil)

            Section {
                Button("보행신호 조회", action: fetch)
                    .disabled(request != nil || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if request != nil {
                    ProgressView("조회 중")
                    Button("조회 취소") { cancel() }
                }
                Text(status)
            }
            ForEach(rows.filter { intersectionID.isEmpty || $0.intersectionID == intersectionID }) { row in
                Section("교차로 \(row.intersectionID)") {
                    SignalObservationView(row: row)
                }
            }
            Section {
                Text("방향은 차량 진입 기준입니다. 예: 북 진입 기준 보행신호는 교차로 서쪽 횡단보도에 대응합니다. 잔여시간은 명세의 1/10초 단위로 변환합니다. 조회 결과는 앱을 종료할 때까지 보관합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("서울시 제공 데이터 · 공식 명세", destination: URL(string: "https://t-data.seoul.go.kr/dataprovide/trafficdataviewopenapi.do?data_id=10339")!)
            }
        }
        .navigationTitle("서울 보행신호")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            cancel()
            apiKey = ""
        }
    }

    private func cancel() {
        generation = UUID()
        request?.cancel()
        request = nil
        status = "조회가 취소되었습니다."
    }

    private func fetch() {
        isEditing = false
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let intersection = intersectionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard intersection.isEmpty || intersection.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            status = "교차로 ID에는 숫자를 입력해 주세요."
            return
        }
        status = "서울시 서버에 연결하고 있습니다."
        let token = UUID()
        generation = token
        request = Task { @MainActor in
            defer { if generation == token { request = nil } }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            do {
                let url = SeoulSignalRow.requestURL(key: key, intersection: intersection)
                let (data, response) = try await session.data(from: url)
                try Task.checkCancellation()
                guard generation == token else { return }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 429 {
                        status = "요청 제한 (HTTP 429). T-Data에서 호출을 제한했습니다. 활용신청 내역의 승인 상태와 사용량·호출 한도를 확인해 주세요. 자동 재시도하지 않습니다."
                        if let raw = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After"),
                           let seconds = Int(raw), seconds >= 0 {
                            status += " 서버 안내: \(seconds)초 후 재시도."
                        }
                    } else {
                        status = "조회 실패 (HTTP \(code)). 인증키와 해당 API의 승인 상태를 확인해 주세요."
                    }
                    return
                }
                let received = try SeoulSignalRow.parse(data)
                if !intersection.isEmpty {
                    guard received.allSatisfy({ $0.intersectionID == intersection }) else {
                        status = "요청한 교차로와 응답 ID가 달라 연결하지 않았습니다."
                        return
                    }
                }
                let replaced = Set(received.map(\.intersectionID)).union(intersection.isEmpty ? [] : [intersection])
                rows.removeAll { replaced.contains($0.intersectionID) }
                rows.append(contentsOf: received)
                status = received.isEmpty
                    ? "응답은 받았지만 보행신호가 포함된 데이터가 없습니다. 교차로 ID를 비워 다시 시도해 주세요."
                    : "보행신호 원본 \(received.count)건 조회 · \(Date.now.formatted(date: .omitted, time: .standard))"
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                // Never display server bodies or URLSession errors: they may contain the key.
                status = "데이터를 확인하지 못했습니다. 네트워크, 인증키, API 승인 상태를 확인해 주세요."
            }
        }
    }
}
