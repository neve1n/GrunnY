import SwiftUI
import MapKit
import Charts

enum GrunnYStyle {
    static let background = Color("GrunnYBackground")
    static let primary = Color("GrunnYPrimary")
    static let secondary = Color("GrunnYSecondary")
    static let brand = Color("GrunnYBrand")
    static let control = Color("GrunnYControl")
    static let soft = Color("GrunnYSoft")
    static let border = Color("GrunnYBorder")
    static let mint = Color("GrunnYMint")
    static let teal = Color("GrunnYTeal")
    static let gradient = LinearGradient(stops: [.init(color: Color("GrunnYGradientStart"), location: 0), .init(color: teal, location: 0.48), .init(color: brand, location: 1)], startPoint: .leading, endPoint: .trailing)
    static func pace(_ seconds: Int) -> String { String(format: "%d'%02d\"", seconds / 60, seconds % 60) }
    static func elapsed(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct CourseLoadingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                Circle()
                    .stroke(AngularGradient(colors: [GrunnYStyle.mint, GrunnYStyle.teal, GrunnYStyle.brand, GrunnYStyle.teal, GrunnYStyle.mint], center: .center), lineWidth: 10)
                    .rotationEffect(.degrees(reduceMotion ? 0 : turns * 360))
            }
            .accessibilityHidden(true)
            Text("코스 탐색중")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(GrunnYStyle.brand)
        }
    }
}

struct GrunnYPrimaryLabel: View {
    let title: String
    var trailingAligned = false
    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Text(title).font(.headline)
            Image("Design-arrow").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            if !trailingAligned { Spacer(minLength: 0) }
        }.padding(.trailing, trailingAligned ? 26 : 0).foregroundStyle(.white).frame(minHeight: 56)
            .background(GrunnYStyle.gradient, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DesignedRouteMap: View {
    let planner: RoutePlanner
    let location: LocationManager
    @State private var position: MapCameraPosition = .automatic
    var body: some View {
        Map(position: $position) {
            ForEach(Array(planner.displayedLegs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(leg.polyline).stroke(.white, lineWidth: 9)
                MapPolyline(leg.polyline).stroke(GrunnYStyle.teal, lineWidth: 5)
            }
            if location.runLocations.count >= 2 {
                MapPolyline(coordinates: location.runLocations.map(\.coordinate)).stroke(GrunnYStyle.brand, lineWidth: 5)
            }
            if let start = planner.displayedLegs.first?.polyline.points()[0].coordinate {
                Annotation("출발", coordinate: start) {
                    Circle().fill(GrunnYStyle.brand).frame(width: 16, height: 16).overlay(Circle().stroke(.white, lineWidth: 4))
                }
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onAppear { fit() }
        .onChange(of: planner.selectedIndex) { _, _ in fit() }
    }
    private func fit() {
        if let bounds = planner.bounds { position = .rect(bounds.insetBy(dx: -max(bounds.width * 0.15, 100), dy: -max(bounds.height * 0.15, 100))) }
        else if let point = location.currentLocation { position = .region(.init(center: point.coordinate, span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005))) }
    }
}

struct DesignedRunSession: View {
    let location: LocationManager
    let planner: RoutePlanner
    let targetPace: Int
    let done: () -> Void
    @State private var showsMap = false
    @State private var confirmsFinish = false
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    if location.isRunning { running(at: context.date) }
                    else { complete(at: context.date) }
                }
                .background {
                    GrunnYStyle.background.overlay(alignment: .top) {
                        LinearGradient(colors: [GrunnYStyle.mint.opacity(location.isRunning ? 0.48 : 0.22), .clear], startPoint: .top, endPoint: .bottom).frame(height: 320)
                    }.ignoresSafeArea()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if location.isRunning {
                    Button { confirmsFinish = true } label: {
                        Text("러닝 종료")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(GrunnYStyle.gradient, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(GrunnYStyle.background)
                } else {
                    Button(action: done) {
                        Text("완료").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(GrunnYStyle.gradient, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(GrunnYStyle.background)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Text("GrunnY").font(.title3.bold()).foregroundStyle(GrunnYStyle.brand).fixedSize() }.sharedBackgroundVisibility(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsMap) {
                NavigationStack {
                    DesignedRouteMap(planner: planner, location: location).ignoresSafeArea(edges: .bottom)
                        .navigationTitle("달리는 경로").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showsMap = false } } }
                }
            }
        }
        .disabled(confirmsFinish)
        .accessibilityHidden(confirmsFinish)
        .overlay {
            if confirmsFinish {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 0) {
                        Text("러닝을 종료할까요?")
                            .font(.system(size: 24, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("종료하면 지금까지의 러닝 기록을\n확인할 수 있어요.")
                            .font(.system(size: 14))
                            .foregroundStyle(GrunnYStyle.secondary)
                            .lineSpacing(6).padding(.top, 16)
                        Button { confirmsFinish = false } label: {
                            Text("계속 달리기").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(GrunnYStyle.gradient, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).padding(.top, 26)
                        Button(role: .destructive) {
                            confirmsFinish = false
                            location.endRun()
                        } label: {
                            Text("러닝 종료").font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.88, green: 0.15, blue: 0.18))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).padding(.top, 16)
                    }
                    .padding(24)
                    .frame(maxWidth: 350, minHeight: 300, alignment: .topLeading)
                    .background(GrunnYStyle.background, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: Color(red: 0.02, green: 0.08, blue: 0.07).opacity(0.18), radius: 32, y: 12)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { confirmsFinish = false }
                }
            }
        }
        .onChange(of: location.isRunning) { _, running in
            if !running { confirmsFinish = false }
        }
        .foregroundStyle(GrunnYStyle.primary).tint(GrunnYStyle.brand)
    }

    private func running(at now: Date) -> some View {
        VStack(spacing: 0) {
            Text("현재 페이스")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(GrunnYStyle.secondary)
                .padding(.top, 70)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(currentPace(at: now))
                    .font(.system(size: 68, weight: .bold))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .monospacedDigit()
                Text("/km").font(.system(size: 18))
                    .foregroundStyle(GrunnYStyle.brand)
            }
            .padding(.top, 12)
            HStack(spacing: 9) {
                Circle().fill(GrunnYStyle.teal).frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text("목표 \(GrunnYStyle.pace(targetPace))/km")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GrunnYStyle.brand)
            }
            .padding(.top, 18)
            Image("Design-flow").resizable().frame(height: 24)
                .accessibilityHidden(true).padding(.top, 28)

            Button { showsMap = true } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("달리는 경로")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GrunnYStyle.brand)
                        Text("지도에서 코스 확인")
                            .font(.system(size: 24, weight: .bold))
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text("선택한 코스와 현재 위치를 확인해요")
                            .font(.system(size: 12))
                            .foregroundStyle(GrunnYStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "map")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(GrunnYStyle.teal, in: Circle())
                }
                .padding(20).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                .background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain).padding(.top, 76)

            Rectangle().fill(GrunnYStyle.border).frame(height: 1).padding(.top, 36)
            HStack(spacing: 40) {
                runningStat("거리", value: String(format: "%.2f km", location.distance / 1000))
                runningStat("시간", value: GrunnYStyle.elapsed(location.elapsedTime(at: now)))
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 20).padding(.bottom, 24)
    }

    private func runningStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(GrunnYStyle.secondary)
            Text(value).font(.system(size: 26, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func complete(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("오늘의 러닝").font(.subheadline).foregroundStyle(GrunnYStyle.brand)
                Text("오늘의 흐름을\n완성했어요").font(.system(.title, weight: .bold))
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    Text(String(format: "%.2f", location.distance / 1000)).font(.system(size: 58, weight: .bold)).monospacedDigit()
                    Text("km").foregroundStyle(GrunnYStyle.secondary)
                }
            }.padding(.top, 16)
            HStack(spacing: 12) {
                stat("평균 페이스", value: averagePace(at: now))
                Rectangle().fill(GrunnYStyle.border).frame(width: 1, height: 56)
                stat("시간", value: GrunnYStyle.elapsed(location.elapsedTime(at: now)))
            }.padding(20).background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 20) {
                Text("페이스 흐름").font(.subheadline).foregroundStyle(GrunnYStyle.brand)
                let points = pacePoints
                if points.count >= 2 {
                    Chart(points, id: \.date) { point in
                        LineMark(x: .value("시간", point.date), y: .value("분/km", point.pace / 60))
                            .foregroundStyle(GrunnYStyle.gradient).lineStyle(.init(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 190)
                } else {
                    Text("페이스를 표시할 GPS 기록이 부족해요.").font(.subheadline).foregroundStyle(GrunnYStyle.secondary)
                        .frame(maxWidth: .infinity, minHeight: 170)
                }
            }.padding(20).background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
        }.padding(20)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label).font(.caption).foregroundStyle(GrunnYStyle.secondary)
            Text(value).font(.system(.title2, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func currentPace(at now: Date) -> String {
        guard let point = location.runLocations.last, now.timeIntervalSince(point.timestamp) < 15,
              point.speed.isFinite, point.speed > 0.5 else { return "—" }
        return GrunnYStyle.pace(Int((1000 / point.speed).rounded()))
    }
    private func averagePace(at now: Date) -> String {
        guard location.distance >= 10 else { return "—" }
        return GrunnYStyle.pace(Int((location.elapsedTime(at: now) / location.distance * 1000).rounded()))
    }
    private var pacePoints: [(date: Date, pace: Double)] {
        location.runLocations.filter { $0.speed.isFinite && $0.speed > 0.5 }.map { ($0.timestamp, 1000 / $0.speed) }
    }
}
