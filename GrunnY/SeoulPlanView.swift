import SwiftUI

struct SeoulPlanView: View {
    @State private var key = ""
    @State private var phaseSearch: PedestrianPhaseSearch?
    @State private var name = ""
    @State private var status = "공공데이터포털 인증키와 서울 교차로 이름을 입력하세요."
    @Binding var result: SeoulPlanCollection?
    @State private var selectedIntersection = ""
    @State private var departure: Date
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()
    @FocusState private var editing: Bool

    init(result: Binding<SeoulPlanCollection?>, departure: Date) {
        _result = result
        _departure = State(initialValue: departure)
    }

    var body: some View {
        Form {
            Section {
                SecureField("공공데이터포털 인증키", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                TextField("서울 교차로 이름 (예: 시청)", text: $name)
                    .autocorrectionDisabled().focused($editing)
            } header: { Text("서울 운영계획 연결") }
              footer: { Text("T-Data 키와 다른 인증키입니다. 키는 파일에 저장하지 않으며 화면을 나가면 지웁니다. 인코딩·디코딩 키 모두 입력할 수 있습니다.") }
                .disabled(task != nil)
            Section {
                Button("전체 계획 수집") { fetch() }
                    .disabled(task != nil || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if task != nil {
                    ProgressView("조회 중")
                    Button("취소", action: cancel)
                }
                Text(status)
            }
            Section("보행현시가 있는 교차로 찾기") {
                Button("서울 보행현시 검색", action: searchPedestrianPhases)
                    .disabled(task != nil || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("교차로 이름 입력 없이 서울 현시 구성에서 P 코드를 찾습니다. 최대 100페이지·페이지당 100건을 순서대로 조회하며 오류 시 중단합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if let search = phaseSearch {
                    Text("\(search.complete ? "전체 조회 완료" : "부분 결과 · 전체 판정 불가") · \(search.pagesRead)페이지 · \(search.rows.count)/\(search.total)건 확인")
                    let candidates = search.candidates
                    Text("보행현시 교차로 후보 \(candidates.count)곳")
                    if candidates.isEmpty {
                        Text(search.complete ? "조회된 서울 기반정보에서 해석 가능한 P 코드를 찾지 못했습니다. 실제 보행신호가 없다는 뜻은 아닙니다." : "확인한 범위에서는 아직 찾지 못했습니다.")
                            .font(.caption)
                    }
                    ForEach(candidates) { candidate in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(candidate.name.isEmpty ? "이름 미제공" : candidate.name) · \(candidate.id)")
                            Text("맵 \(candidate.maps.joined(separator: ", ")) · P 현시 \(candidate.phaseCount)개")
                                .font(.caption)
                            Button("이 교차로 계획·기반정보 수집") {
                                name = candidate.name
                                fetch(preferredID: candidate.id)
                            }
                            .disabled(task != nil || candidate.name.isEmpty || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Text("P 코드가 있어도 실제 횡단보도 대응과 녹색 시간 검증 전에는 신호 최적화 코스로 사용하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let result {
                Section("조회 결과") {
                    Text("검색: \(result.query) · 모든 페이지 수집 완료")
                    Text("조회: \(result.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                    ForEach(SeoulPlanKind.allCases, id: \.self) { kind in
                        LabeledContent(kind.label, value: "\(result.tables[kind]?.count ?? 0)건")
                    }
                }
                Section("출발 시각의 계획 후보") {
                    DatePicker("출발 시각 (한국 시간)", selection: $departure)
                        .environment(\.timeZone, TimeZone(identifier: "Asia/Seoul")!)
                    Picker("교차로", selection: $selectedIntersection) {
                        Text("교차로 선택").tag("")
                        ForEach(result.intersectionIDs, id: \.self) { id in
                            Text("\(result.operations.first { $0["INT_NO"] == id }?["INT_NM"] ?? "교차로") · \(id)").tag(id)
                        }
                    }
                    if !selectedIntersection.isEmpty {
                        switch result.selection(intersectionID: selectedIntersection, at: departure) {
                        case .candidate(let row):
                            LabeledContent("계획 / 인덱스", value: "\(row["INT_PLAN_NO"] ?? "?") / \(row["INT_PLAN_IDX_NO"] ?? "?")")
                            LabeledContent("운영주기 원본", value: row["INT_OPER_CYCLE_VAL"] ?? "?")
                            LabeledContent("옵셋 원본", value: row["INT_OPER_OFFSET_VAL"] ?? "?")
                            Text("요일·시간 조건에 맞는 후보입니다. 실제 운영 상태와 보행현시 대응은 추가 검증이 필요합니다.")
                        case .unavailable(let reason): Text(reason)
                        }
                    }
                }
                Section("보행현시 구성정보") {
                    Button("기반정보 수집", action: fetchBasis)
                        .disabled(task != nil || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("위 인증키로 ‘\(result.query)’의 교차로·현시 구성을 조회합니다. 교차로기반정보서비스 활용 승인이 필요합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("기반정보 API 활용신청", destination: URL(string: "https://www.data.go.kr/data/15056721/openapi.do")!)
                    if let basis = result.basis {
                        Text("교차로 \(basis.intersections.count)건 · 현시 구성 \(basis.configurations.count)건 · 전체 페이지 수집 완료")
                        Text("조회: \(basis.fetchedAt.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption)
                        if selectedIntersection.isEmpty {
                            Text("위에서 교차로를 선택하세요.")
                        } else {
                            let configurations = basis.configurations(for: selectedIntersection)
                            if configurations.isEmpty {
                                Text("선택한 운영계획과 번호가 일치하는 기반정보가 없거나 교차로가 중복됩니다.")
                            } else {
                                Text("경찰청 교차로 번호 \(selectedIntersection) 일치 · 적용 맵은 아직 미확정")
                                ForEach(Array(configurations.prefix(20).enumerated()), id: \.offset) { _, row in
                                    PhaseConfigurationRows(row: row)
                                }
                                if configurations.count > 20 { Text("현시 구성 미리보기는 첫 20건입니다.") }
                            }
                        }
                    }
                    Text("P는 보행자 현시입니다. 진입·진출각만으로 횡단보도 위치나 초록불 지속시간을 확정하지 않습니다. 대기시간 계산은 아직 미적용입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("원본 미리보기는 운영계획의 첫 100건입니다. 전체 데이터는 앱 메모리에 보관됩니다.")
                        .font(.caption)
                }
                ForEach(Array(result.operations.prefix(100).enumerated()), id: \.offset) { _, row in
                    Section("\(row["INT_NM"] ?? "교차로") · 계획 \(row["INT_PLAN_NO"] ?? "?")") {
                        LabeledContent("운영계획 교차로 번호", value: row["INT_NO"] ?? "없음")
                        LabeledContent("계획 인덱스", value: row["INT_PLAN_IDX_NO"] ?? "없음")
                        LabeledContent("적용 시각", value: "\(row["OPER_PLAN_HH"] ?? "?")시 \(row["OPER_PLAN_MI"] ?? "?")분")
                        LabeledContent("운영주기 원본", value: row["INT_OPER_CYCLE_VAL"] ?? "없음")
                        LabeledContent("옵셋 원본", value: row["INT_OPER_OFFSET_VAL"] ?? "없음")
                        LabeledContent("원본 수집 시각", value: row["COLLCT_DTIME"] ?? "제공되지 않음")
                        ForEach(["A", "B"], id: \.self) { ring in
                            let values = (1...8).map { row["\(ring)_RING_\($0)_PHASE_VAL"] ?? "?" }.joined(separator: " / ")
                            LabeledContent("\(ring)링 현시 1~8", value: values)
                        }
                    }
                }
            }
            Section {
                Text("운영·요일·특수일·예약계획을 순서대로 수집합니다. 각 최대 20페이지이며 오류 시 중단합니다. A/B링 시간을 보행신호 시간으로 간주하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("경찰청 제공 · 공식 명세", destination: URL(string: "https://www.data.go.kr/data/15056569/openapi.do")!)
            }
        }
        .navigationTitle("서울 신호 운영계획")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { cancel(); key = "" }
    }

    private func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        status = "조회가 취소되었습니다."
    }

    private func fetch(preferredID: String? = nil) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, (1...30).contains(name.count), task == nil else { return }
        editing = false
        status = "서울 운영계획 조회 중…"
        let token = UUID()
        generation = token
        task = Task { @MainActor in
            var collectBasisAfterSuccess = false
            defer {
                if generation == token {
                    task = nil
                    if collectBasisAfterSuccess { fetchBasis() }
                }
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            config.urlCache = nil
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            var stage = "조회 준비"
            var completedPages = 0
            do {
                var tables: [SeoulPlanKind: [[String: String]]] = [:]
                for kind in SeoulPlanKind.allCases {
                    var accumulator = PlanPageAccumulator()
                    while !accumulator.isComplete {
                        try Task.checkCancellation()
                        guard generation == token else { return }
                        stage = "\(kind.label) · \(accumulator.nextPage)페이지"
                        status = stage + " 수집 중"
                        let url = SeoulPlanPage.url(key: key, name: name, kind: kind, page: accumulator.nextPage)
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            throw SeoulPlanPage.responseFailure(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
                        }
                        let page = try SeoulPlanPage.decode(data, kind: kind)
                        try accumulator.append(page)
                        completedPages += 1
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    tables[kind] = accumulator.rows
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                let collected = SeoulPlanCollection(query: name, fetchedAt: .now, tables: tables)
                result = collected
                selectedIntersection = preferredID.flatMap { collected.intersectionIDs.contains($0) ? $0 : nil }
                    ?? (collected.intersectionIDs.count == 1 ? collected.intersectionIDs[0] : "")
                collectBasisAfterSuccess = preferredID != nil && !selectedIntersection.isEmpty
                status = collected.operations.isEmpty ? "이 이름으로 조회되는 서울 운영계획이 없습니다." : "4종 계획 전체 페이지 수집 완료 · 보행신호 대응 검증 전"
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                let reason = (error as? PlanFailure)?.errorDescription ?? "조회에 실패했습니다. 네트워크와 서비스 상태를 확인해 주세요."
                status = "교차로계획정보서비스 · \(stage) 실패\n완료한 페이지: \(completedPages)\n\(reason)"
            }
        }
    }

    private func searchPedestrianPhases() {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, task == nil else { return }
        editing = false
        let token = UUID()
        generation = token
        phaseSearch = PedestrianPhaseSearch()
        task = Task { @MainActor in
            defer { if generation == token { task = nil } }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            config.urlCache = nil
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            var accumulator = PlanPageAccumulator(maximumPages: 100)
            do {
                while !accumulator.isComplete {
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    status = "서울 보행현시 검색 · \(accumulator.nextPage)페이지"
                    let url = SeoulPhaseBasis.url(key: key, name: "", detail: true, page: accumulator.nextPage)
                    let (data, response) = try await session.data(from: url)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw SeoulPlanPage.responseFailure(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
                    }
                    let page = try SeoulPlanPage.decode(data, recordElement: "CrossRoadInfoDetail")
                    do {
                        try accumulator.append(page)
                    } catch let failure as PlanFailure {
                        if case .countMismatch = failure, generation == token, !Task.isCancelled {
                            // The row parser succeeded but completeness failed. Keep these
                            // records for P discovery only, explicitly as partial results.
                            phaseSearch = PedestrianPhaseSearch(rows: accumulator.rows + page.rows, complete: false,
                                                               total: page.total, pagesRead: page.page)
                        }
                        throw failure
                    }
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    phaseSearch = PedestrianPhaseSearch(rows: accumulator.rows, complete: accumulator.isComplete,
                                                       total: page.total, pagesRead: accumulator.nextPage - 1)
                    if !accumulator.isComplete { try await Task.sleep(for: .seconds(1)) }
                }
                status = "서울 기반정보 전체 검색 완료 · P 보행현시 후보 \(phaseSearch?.candidates.count ?? 0)곳"
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                let reason = (error as? PlanFailure)?.errorDescription ?? "네트워크 또는 서비스 상태를 확인해 주세요."
                status = "서울 보행현시 검색 · \(accumulator.nextPage)페이지에서 중단\n\(reason)\n확인한 부분 결과만 유지합니다."
            }
        }
    }

    private func fetchBasis() {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = result, !key.isEmpty, task == nil else { return }
        editing = false
        let token = UUID()
        generation = token
        task = Task { @MainActor in
            defer { if generation == token { task = nil } }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 30
            config.urlCache = nil
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            var stage = "조회 준비"
            var completedPages = 0
            do {
                var collected: [[[String: String]]] = []
                for detail in [false, true] {
                    var accumulator = PlanPageAccumulator()
                    while !accumulator.isComplete {
                        try Task.checkCancellation()
                        guard generation == token else { return }
                        stage = "\(detail ? "현시 구성" : "교차로 기반정보") · \(accumulator.nextPage)페이지"
                        status = stage + " 수집 중"
                        let url = SeoulPhaseBasis.url(key: key, name: current.query, detail: detail, page: accumulator.nextPage)
                        let (data, response) = try await session.data(from: url)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            throw SeoulPlanPage.responseFailure(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
                        }
                        let page = try SeoulPlanPage.decode(data, recordElement: detail ? "CrossRoadInfoDetail" : "CrossRoadInfoList")
                        try accumulator.append(page)
                        completedPages += 1
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    collected.append(accumulator.rows)
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                var updated = current
                updated.basis = SeoulPhaseBasis(fetchedAt: .now, intersections: collected[0], configurations: collected[1])
                result = updated
                status = "기반정보 수집 완료 · 교차로를 선택해 보행현시를 확인하세요."
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                let reason = (error as? PlanFailure)?.errorDescription ?? "기반정보 조회에 실패했습니다. 네트워크와 서비스 상태를 확인해 주세요."
                status = "교차로기반정보서비스 · \(stage) 실패\n완료한 페이지: \(completedPages)\n\(reason)"
            }
        }
    }
}

private struct PhaseConfigurationRows: View {
    let row: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("맵 \(row["MAP_NO"] ?? "미제공")").font(.headline)
            ForEach(["A", "B"], id: \.self) { ring in
                ForEach(1...8, id: \.self) { phase in
                    let raw = row["\(ring)_RING_\(phase)_PHASE_CONF_CD"] ?? ""
                    if !raw.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ring)링 \(phase)현시 · \(raw)").font(.subheadline)
                            Text(PolicePhaseCode(raw)?.label ?? "해석되지 않은 원본 코드")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !["A", "B"].contains(where: { ring in
                (1...8).contains { PolicePhaseCode(row["\(ring)_RING_\($0)_PHASE_CONF_CD"] ?? "")?.isPedestrian == true }
            }) {
                Text("이 맵에는 해석 가능한 P 보행현시가 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
