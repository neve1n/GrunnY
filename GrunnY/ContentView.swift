import SwiftUI
import MapKit

struct ContentView: View {
    @State private var location = LocationManager()
    @State private var planner = RoutePlanner()
    @AppStorage("targetDistanceKM") private var targetKM = 5.0
    @AppStorage("paceSecondsPerKM") private var pace = 330
    @State private var departure: Date?
    @State private var clockTime = Date().addingTimeInterval(300)
    @State private var departsNow = false
    @State private var signalRows: [SeoulSignalRow] = []
    @State private var plans: SeoulPlanCollection?
    @State private var showsTools = false
    @State private var showsRoute = false
    @State private var showsSession = false
    @State private var showsAnalysis = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedStart: RunStartPoint?
    @State private var showsGoal = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            StartLocationView(location: location, selection: $selectedStart) {
                planner.clear()
                showsGoal = true
            }
            .navigationDestination(isPresented: $showsGoal) {
                Group {
                    if planner.isLoading { loading }
                    else { goal }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showsRoute) { routeScreen }
            }
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
        .sheet(isPresented: $showsAnalysis, onDismiss: refreshSignalRecommendation) {
            RouteComparisonView(assessments: planner.signalAssessments(pace: pace, plans: plans, signalRows: signalRows), pace: pace,
                                departure: planner.calculatedDeparture ?? .now, selectedIndex: planner.selectedIndex,
                                canSelect: !location.isRunning, target: targetKM * 1000,
                                select: { planner.selectCandidate($0) }, plans: $plans, signalRows: $signalRows)
        }
        .fullScreenCover(isPresented: $showsSession) {
            DesignedRunSession(location: location, planner: planner, targetPace: pace) {
                showsRoute = false
                showsGoal = false
                selectedStart = nil
                showsSession = false
            }
                .preferredColorScheme(.light)
        }
        .onChange(of: location.isRunning) { _, running in
            if running {
                if showsTools { showsTools = false } else { showsSession = true }
            }
        }
    }

    private var brand: some View {
        Text("GrunnY").font(.system(.title3, weight: .bold)).foregroundStyle(GrunnYStyle.brand)
    }

    private var goal: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button { showsGoal = false } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("출발지 선택으로 돌아가기")
                        Spacer()
                        brand
                    }.frame(height: 44)
                    Text("오늘은 어떻게\n달려볼까요?")
                        .font(.system(size: 28, weight: .bold)).lineSpacing(2).padding(.top, 4)
                    Color.clear.frame(height: 28)
                    goalControl("DISTANCE", value: String(format: "%.1f km", targetKM),
                                minus: { changeDistance(-0.5) }, plus: { changeDistance(0.5) },
                                canMinus: targetKM > 0.5, canPlus: targetKM < 42)
                    Color.clear.frame(height: 68)
                    goalControl("PACE", value: GrunnYStyle.pace(pace) + "/km",
                                minus: { changePace(-5) }, plus: { changePace(5) },
                                canMinus: pace > 180, canPlus: pace < 900)
                    Color.clear.frame(height: 68)
                    Text("START TIME").font(.system(size: 12, weight: .bold)).tracking(0.8).foregroundStyle(GrunnYStyle.secondary)
                    GoalTimeWheel(date: $clockTime) {
                        departsNow = false
                        planner.clear()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
                    .overlay { Text(":").font(.system(size: 24, weight: .bold)).accessibilityHidden(true).allowsHitTesting(false) }
                    .padding(.top, 8)
                    if let message = planner.message {
                        Text(message).font(.footnote).foregroundStyle(GrunnYStyle.brand).padding(.top, 8)
                    }

                }
                .padding(.horizontal, 20).padding(.bottom, 12)
                .frame(minHeight: max(0, geometry.size.height - 12), alignment: .topLeading)
            }
        }
        .background(GrunnYStyle.background)
        .safeAreaInset(edge: .bottom) {
            Button(action: findCourse) { GrunnYPrimaryLabel(title: "코스 찾기", trailingAligned: true) }
                .buttonStyle(.plain).disabled(selectedStart == nil)
                .opacity(selectedStart == nil ? 0.5 : 1)
                .padding(.horizontal, 20).padding(.vertical, 12).background(GrunnYStyle.background)
        }
    }

    private func goalControl(_ title: String, value: String, minus: @escaping () -> Void,
                             plus: @escaping () -> Void, canMinus: Bool, canPlus: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 12, weight: title == "PACE" ? .bold : .regular)).tracking(0.8).foregroundStyle(GrunnYStyle.secondary)
            HStack {
                Button(action: minus) { Image("Design-minus").resizable().frame(width: 20, height: 20).frame(width: 44, height: 44).background(GrunnYStyle.control, in: Circle()) }
                    .disabled(!canMinus).accessibilityLabel(title == "PACE" ? "페이스 5초 줄이기" : "거리 0.5킬로미터 줄이기")
                Spacer(minLength: 8)
                Text(value).font(.system(size: 28, weight: .bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Spacer(minLength: 8)
                Button(action: plus) { Image("Design-plus").resizable().frame(width: 20, height: 20).frame(width: 44, height: 44).background(GrunnYStyle.control, in: Circle()) }
                    .disabled(!canPlus).accessibilityLabel(title == "PACE" ? "페이스 5초 늘리기" : "거리 0.5킬로미터 늘리기")
            }.buttonStyle(.plain)
            Rectangle().fill(GrunnYStyle.border).frame(height: 1)
        }
    }

    private var loading: some View {
        VStack(alignment: .leading) {
            brand
            Text("달릴 길을\n찾고 있어요.").font(.system(.title, weight: .bold)).padding(.top, 40)
            Spacer()
            CourseLoadingRing()
                .frame(width: 156, height: 156).frame(maxWidth: .infinity)
            Text(planner.progress).font(.caption).foregroundStyle(GrunnYStyle.secondary).frame(maxWidth: .infinity).padding(.top, 24)
            Spacer()
            Button("취소") { searchTask?.cancel(); planner.clear() }.frame(maxWidth: .infinity, minHeight: 44)
        }.padding(20).background(GrunnYStyle.background)
    }

    private var routeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { showsRoute = false } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, -10)
                .accessibilityLabel("뒤로")

                Text("달릴 길을 찾았어요.")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                DesignedRouteMap(planner: planner, location: location)
                    .aspectRatio(350.0 / 368.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: GrunnYStyle.brand.opacity(0.07), radius: 16, y: 8)

                HStack(spacing: 20) {
                    metric(String(format: "%.1f km", planner.distance / 1000), "거리")
                    metric("\(Int(ceil((planner.distance / 1000 * Double(pace) + (planner.selectedSignalEstimate?.totalWait ?? 0)) / 60))) min",
                           planner.selectedSignalEstimate?.totalWait == nil ? "예상 시간 · 대기 제외" : "예상 시간 · 대기 포함")
                }
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(GrunnYStyle.pace(pace) + "/km")
                        .font(.system(size: 24, weight: .bold))
                    caption("목표 페이스")
                }
                .padding(.top, 18)

                HStack(alignment: .center, spacing: 12) {
                    Circle().fill(GrunnYStyle.teal).frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text(planner.recommendedSignalRouteID == planner.selectedLoop?.id && planner.recommendedSignalRouteID != nil
                         ? "비교 가능한 후보 중 예상 신호 대기가 가장 적은 코스예요."
                         : "신호 대기시간은 아직 확인되지 않았어요. 자료가 있는 후보끼리는 신호등 없는 횡단보도 근접을 줄여 선택해요.")
                        .font(.system(size: 14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(GrunnYStyle.brand)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(GrunnYStyle.mint, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 20)
                Button { showsAnalysis = true } label: {
                    HStack {
                        Text(planner.selectedSignalEstimate?.totalWait.map { "예상 신호 대기 \(Int($0.rounded()))초 · 분석 보기" }
                             ?? "신호 대기 미확인 · 데이터 확인")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption).foregroundStyle(GrunnYStyle.brand)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(GrunnYStyle.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if location.isDenied || location.isRestricted {
                    Text("러닝 기록에는 위치 권한이 필요해요.").font(.caption).foregroundStyle(GrunnYStyle.secondary)
                }
                Button {
                    if location.canStartRun { location.startRun() }
                    else if location.isDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } else { location.requestCurrentLocation() }
                } label: {
                    GrunnYPrimaryLabel(title: location.canStartRun ? "이 코스로 달리기" : "위치 권한 허용", trailingAligned: true)
                }
                .buttonStyle(.plain).disabled(location.isRestricted || location.isRunning || planner.displayedLegs.isEmpty)
            }
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
            await planner.findLoops(from: location.currentLocation, targetKM: targetKM, pace: pace,
                                    departure: departure, selectedStart: selectedStart?.coordinate)
            refreshSignalRecommendation()
            if !Task.isCancelled, !planner.displayedLegs.isEmpty { showsRoute = true }
        }
    }

    private func refreshSignalRecommendation() {
        guard !location.isRunning else { return }
        planner.applySignalAssessments(planner.signalAssessments(pace: pace, plans: plans, signalRows: signalRows))
    }
}

#Preview { ContentView() }
