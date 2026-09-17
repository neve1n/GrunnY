import SwiftUI
import MapKit

struct ContentView: View {
    @State private var location = LocationManager()
    @State private var planner = RoutePlanner()
    @AppStorage("targetDistanceKM") private var targetKM = 5.0
    @AppStorage("paceSecondsPerKM") private var pace = 330
    @State private var departure: Date?
    @State private var clockTime = Date().addingTimeInterval(300)
    @State private var departsNow = true
    @State private var signalRows: [SeoulSignalRow] = []
    @State private var plans: SeoulPlanCollection?
    @State private var showsTools = false
    @State private var showsRoute = false
    @State private var showsSession = false
    @State private var showsAnalysis = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if planner.isLoading { loading }
                else { goal }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { brand.fixedSize() }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("지도·연결", systemImage: "map") { showsTools = true }
                        .disabled(planner.isLoading)
                }
            }
            .navigationDestination(isPresented: $showsRoute) { routeScreen }
        }
        .tint(GrunnYStyle.brand)
        .foregroundStyle(GrunnYStyle.primary)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showsTools, onDismiss: { if location.isRunning { showsSession = true } }) {
            NavigationStack {
                MapWorkspaceView(location: location, routePlanner: planner, departureTime: $departure,
                                 signalRows: $signalRows, signalPlans: $plans)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showsTools = false } } }
            }
        }
        .sheet(isPresented: $showsAnalysis) {
            RouteComparisonView(assessments: planner.signalAssessments(pace: pace, plans: plans), pace: pace,
                                departure: planner.calculatedDeparture ?? .now, selectedIndex: planner.selectedIndex,
                                canSelect: !location.isRunning, target: targetKM * 1000,
                                select: { planner.selectCandidate($0) }, plans: $plans)
        }
        .fullScreenCover(isPresented: $showsSession) {
            DesignedRunSession(location: location, planner: planner, targetPace: pace) { showsSession = false }
                .preferredColorScheme(.light)
        }
        .onChange(of: location.isRunning) { _, running in
            if running {
                if showsTools { showsTools = false } else { showsSession = true }
            }
        }
        .task { location.requestCurrentLocation() }
    }

    private var brand: some View {
        Text("GrunnY").font(.system(.title3, weight: .bold)).foregroundStyle(GrunnYStyle.brand)
    }

    private var goal: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("오늘은 어떻게\n달려볼까요?")
                        .font(.system(.title, weight: .bold)).lineSpacing(2).padding(.top, 12)
                    Spacer(minLength: 28)
                    goalControl("DISTANCE", value: String(format: "%.1f km", targetKM),
                                minus: { changeDistance(-0.5) }, plus: { changeDistance(0.5) },
                                canMinus: targetKM > 0.5, canPlus: targetKM < 42)
                    Spacer(minLength: 36)
                    goalControl("PACE", value: GrunnYStyle.pace(pace) + "/km",
                                minus: { changePace(-5) }, plus: { changePace(5) },
                                canMinus: pace > 180, canPlus: pace < 900)
                    Spacer(minLength: 32)
                    HStack {
                        caption("START TIME")
                        Spacer()
                        Toggle("지금 출발", isOn: $departsNow).font(.caption).fixedSize()
                    }
                    DatePicker("출발 시각", selection: $clockTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity).frame(height: 150).clipped()
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                        .opacity(departsNow ? 0.45 : 1).disabled(departsNow)
                    if !departsNow { Text(clockTime.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(GrunnYStyle.secondary) }
                    if let message = planner.message {
                        Text(message).font(.footnote).foregroundStyle(GrunnYStyle.brand).padding(.top, 8)
                    }
                    if !location.canStartRun {
                        Text(location.message).font(.footnote).foregroundStyle(GrunnYStyle.secondary).padding(.top, 8)
                        Button("위치 다시 확인", action: location.requestCurrentLocation).font(.footnote)
                    }
                    if !planner.displayedLegs.isEmpty {
                        Button("찾아둔 코스 보기") { showsRoute = true }.padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
                .frame(minHeight: max(0, geometry.size.height - 12), alignment: .topLeading)
            }
        }
        .background(GrunnYStyle.background)
        .safeAreaInset(edge: .bottom) {
            Button(action: findCourse) { GrunnYPrimaryLabel(title: "코스 찾기") }
                .buttonStyle(.plain).disabled(!location.canStartRun)
                .opacity(location.canStartRun ? 1 : 0.5)
                .padding(.horizontal, 20).padding(.vertical, 12).background(GrunnYStyle.background)
        }
    }

    private func goalControl(_ title: String, value: String, minus: @escaping () -> Void,
                             plus: @escaping () -> Void, canMinus: Bool, canPlus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            caption(title)
            HStack {
                Button(action: minus) { Image("Design-minus").resizable().frame(width: 20, height: 20).frame(width: 44, height: 44).background(GrunnYStyle.control, in: Circle()) }
                    .disabled(!canMinus).accessibilityLabel(title == "PACE" ? "페이스 5초 줄이기" : "거리 0.5킬로미터 줄이기")
                Spacer(minLength: 8)
                Text(value).font(.system(.title, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Spacer(minLength: 8)
                Button(action: plus) { Image("Design-plus").resizable().frame(width: 20, height: 20).frame(width: 44, height: 44).background(GrunnYStyle.control, in: Circle()) }
                    .disabled(!canPlus).accessibilityLabel(title == "PACE" ? "페이스 5초 늘리기" : "거리 0.5킬로미터 늘리기")
            }.buttonStyle(.plain)
            Rectangle().fill(GrunnYStyle.border).frame(height: 1)
        }
    }

    private var loading: some View {
        VStack(alignment: .leading) {
            Text("달릴 길을\n찾고 있어요.").font(.system(.title, weight: .bold)).padding(.top, 40)
            Spacer()
            ZStack {
                Circle().stroke(GrunnYStyle.gradient, lineWidth: 10)
                VStack(spacing: 12) {
                    ProgressView().tint(GrunnYStyle.brand)
                    Text("코스 만드는 중").font(.subheadline.weight(.medium))
                }
            }.frame(width: 156, height: 156).frame(maxWidth: .infinity)
            Text(planner.progress).font(.caption).foregroundStyle(GrunnYStyle.secondary).frame(maxWidth: .infinity).padding(.top, 24)
            Spacer()
            Button("취소") { searchTask?.cancel(); planner.clear() }.frame(maxWidth: .infinity, minHeight: 44)
        }.padding(20).background(GrunnYStyle.background)
    }

    private var routeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("달릴 길을 찾았어요.").font(.system(.title, weight: .bold))
                DesignedRouteMap(planner: planner, location: location).frame(height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: GrunnYStyle.brand.opacity(0.1), radius: 12, y: 8)
                HStack {
                    metric(String(format: "%.2f km", planner.distance / 1000), "거리")
                    metric("\(Int(ceil(planner.distance / 1000 * Double(pace) / 60))) min", "예상 시간 · 대기 제외")
                }
                HStack(spacing: 12) {
                    Text(GrunnYStyle.pace(pace) + "/km").font(.title3.bold())
                    caption("목표 페이스")
                }
                Text("보행 가능한 경로예요. 신호 대기·경사도는 아직 반영되지 않았어요.")
                    .font(.subheadline).foregroundStyle(GrunnYStyle.brand)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GrunnYStyle.mint, in: RoundedRectangle(cornerRadius: 12))
                if planner.candidates.count > 1 {
                    Picker("코스 후보", selection: Binding(get: { planner.selectedIndex }, set: { planner.selectCandidate($0) })) {
                        ForEach(Array(planner.candidates.enumerated()), id: \.element.id) { index, candidate in
                            Text(String(format: "%.2f km", candidate.distance / 1000)).tag(index)
                        }
                    }.pickerStyle(.segmented)
                }
                Button("코스별 신호 분석") { showsAnalysis = true }.font(.footnote)
                if let message = planner.message { Text(message).font(.footnote) }
            }.padding(20)
        }
        .background(GrunnYStyle.background)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { location.startRun() } label: { GrunnYPrimaryLabel(title: "이 코스로 달리기") }
                .buttonStyle(.plain).disabled(!location.canStartRun || planner.displayedLegs.isEmpty)
                .padding(.horizontal, 20).padding(.vertical, 12).background(GrunnYStyle.background)
        }
    }

    private func caption(_ value: String) -> some View { Text(value).font(.caption).foregroundStyle(GrunnYStyle.secondary) }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(.title, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1); caption(label) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func changeDistance(_ delta: Double) { targetKM = min(42, max(0.5, targetKM + delta)); planner.clear() }
    private func changePace(_ delta: Int) { pace = min(900, max(180, pace + delta)); planner.clear() }
    private func findCourse() {
        departure = departsNow ? nil : clockTime
        searchTask = Task { @MainActor in
            await planner.findLoops(from: location.currentLocation, targetKM: targetKM, pace: pace, departure: departure)
            if !Task.isCancelled, !planner.displayedLegs.isEmpty { showsRoute = true }
        }
    }
}

#Preview { ContentView() }
