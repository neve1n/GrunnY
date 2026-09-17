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
    @State private var runPresentation: RunPresentation?
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
        .sheet(isPresented: $showsTools, onDismiss: { if location.isRunning { runPresentation = RunPresentation(countdown: false) } }) {
            NavigationStack {
                MapWorkspaceView(location: location, routePlanner: planner, departureTime: $departure,
                                 signalRows: $signalRows, signalPlans: $plans)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showsTools = false } } }
            }
        }
        .fullScreenCover(item: $runPresentation) { presentation in
            RunSessionFlow(location: location, planner: planner, targetPace: pace,
                           countdown: presentation.countdown) {
                showsRoute = false
                showsGoal = false
                selectedStart = nil
                runPresentation = nil
            } cancel: {
                runPresentation = nil
            }
            .preferredColorScheme(.light)
        }
        .onChange(of: location.isRunning) { _, running in
            if running {
                if showsTools { showsTools = false }
                else if runPresentation == nil {
                    runPresentation = RunPresentation(countdown: false)
                }
            }
        }
    }

    private var goal: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button { showsGoal = false } label: {
                            Text("뒤로").font(.subheadline).frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("출발지 선택으로 돌아가기")
                        Spacer()
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
            Button(action: findCourse) { GrunnYPrimaryLabel(title: "코스 찾기") }
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
        CourseSearchLoadingView(progress: planner.progress) {
            searchTask?.cancel()
            planner.clear()
        }
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
                    .aspectRatio(350.0 / 300.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                Text(planner.message ?? "설정한 거리와 페이스에 맞춰 찾은 코스예요.")
                    .font(.footnote)
                    .foregroundStyle(GrunnYStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                if planner.candidates.count > 1 {
                    HStack(spacing: 0) {
                        ForEach(Array(planner.candidates.enumerated()), id: \.element.id) { index, candidate in
                            courseOption(candidate, index: index)
                        }
                    }
                    .padding(.top, 16)
                }

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("예상 신호 대기")
                            .font(.subheadline).foregroundStyle(GrunnYStyle.secondary)
                        Text(selectedSignalWait.map { "\(Int($0.rounded()))초" } ?? "—")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(GrunnYStyle.primary)
                        Text("주기 정보가 없으면 120초·빨간불 50%를 가정해요. 실제 신호와 대기 시간은 달라요.")
                            .font(.caption).foregroundStyle(GrunnYStyle.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    Rectangle().fill(GrunnYStyle.border).frame(height: 1)

                    HStack(alignment: .top, spacing: 20) {
                        metric(String(format: "%.1f km", planner.distance / 1000), "거리")
                        metric("\(Int(ceil((planner.distance / 1000 * Double(pace) + (planner.selectedSignalEstimate?.totalWait ?? 0)) / 60))) min",
                               planner.selectedSignalEstimate?.totalWait == nil ? "예상 시간 · 대기 제외" : "예상 시간 · 추정 대기 포함")
                    }.padding(.top, 16)
                    HStack(alignment: .top, spacing: 20) {
                        metric(GrunnYStyle.pace(pace) + "/km", "목표 페이스")
                        metric(nearbySignalCount.map { "\($0)개" } ?? "미확인", "주변 신호 횡단보도")
                    }.padding(.top, 20)
                }
                .padding(.horizontal, 8)
                .padding(.top, 28)
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
                    if location.canStartRun {
                        runPresentation = RunPresentation(countdown: true)
                    }
                    else if location.isDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } else { location.requestCurrentLocation() }
                } label: {
                    GrunnYPrimaryLabel(title: "이 코스로 달리기")
                }
                .buttonStyle(.plain).disabled(location.isRestricted || location.isRunning || planner.displayedLegs.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(GrunnYStyle.background)
        }
    }

    private func courseOption(_ candidate: LoopCandidate, index: Int) -> some View {
        let selected = index == planner.selectedIndex
        return Button { planner.selectCandidate(index) } label: {
            VStack(spacing: 6) {
                Text("코스 \(index + 1)")
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? GrunnYStyle.brand : GrunnYStyle.secondary)
                Rectangle()
                    .fill(selected ? GrunnYStyle.brand : .clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(location.isRunning)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("지도와 코스 정보를 변경합니다")
    }

    private var nearbySignalCount: Int? {
        guard planner.crosswalkDataAvailable, !planner.crosswalkMatches.isEmpty else { return nil }
        return Set(planner.crosswalkMatches.filter { $0.crosswalk.signalPresence == "유" }
            .map { $0.crosswalk.id }).count
    }

    private var selectedSignalWait: Double? {
        guard let estimate = planner.selectedSignalEstimate,
              estimate.unavailableReason == nil,
              let wait = estimate.totalWait, wait.isFinite, wait >= 0 else { return nil }
        return wait
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
            planner.selectCandidate(0)
            if !Task.isCancelled, !planner.displayedLegs.isEmpty { showsRoute = true }
        }
    }

    private func refreshSignalRecommendation() {
        guard !location.isRunning else { return }
        planner.applySignalAssessments(planner.signalAssessments(pace: pace, plans: plans, signalRows: signalRows))
    }
}

#Preview { ContentView() }
