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

struct GrunnYPrimaryLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            Text(title).font(.headline)
            Image("Design-arrow").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            Spacer(minLength: 0)
        }.foregroundStyle(.white).frame(minHeight: 56)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Text("GrunnY").font(.title3.bold()).foregroundStyle(GrunnYStyle.brand).fixedSize() }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { Button("지도", systemImage: "map") { showsMap = true } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("러닝을 종료할까요?", isPresented: $confirmsFinish, titleVisibility: .visible) {
                Button("러닝 종료", role: .destructive, action: location.endRun)
                Button("계속 달리기", role: .cancel) { }
            }
            .sheet(isPresented: $showsMap) {
                NavigationStack {
                    DesignedRouteMap(planner: planner, location: location).ignoresSafeArea(edges: .bottom)
                        .navigationTitle("달리는 경로").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { showsMap = false } } }
                }
            }
        }.foregroundStyle(GrunnYStyle.primary).tint(GrunnYStyle.brand)
    }

    private func running(at now: Date) -> some View {
        VStack(spacing: 28) {
            VStack(spacing: 16) {
                Text("현재 페이스").font(.subheadline).foregroundStyle(GrunnYStyle.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(currentPace(at: now)).font(.system(size: 64, weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
                    Text("/km").foregroundStyle(GrunnYStyle.brand)
                }.monospacedDigit()
                Text("●  목표 \(GrunnYStyle.pace(targetPace))/km").font(.subheadline).foregroundStyle(GrunnYStyle.brand)
                    .padding(.horizontal, 18).padding(.vertical, 10).background(.white.opacity(0.82), in: Capsule())
                Image("Design-flow").resizable().frame(height: 24).accessibilityHidden(true).padding(.top, 12)
            }.padding(.top, 24)
            Button { showsMap = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("달리는 경로").font(.caption).foregroundStyle(GrunnYStyle.brand)
                        Text("지도에서 코스를 확인하세요").font(.title3.bold())
                        Text("\(location.message)").font(.caption).foregroundStyle(GrunnYStyle.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "map").font(.title2).foregroundStyle(GrunnYStyle.brand)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
            VStack(spacing: 20) {
                Rectangle().fill(GrunnYStyle.border).frame(height: 1)
                HStack {
                    stat("거리", value: String(format: "%.2f km", location.distance / 1000))
                    stat("시간", value: GrunnYStyle.elapsed(location.elapsedTime(at: now)))
                }
            }
            HStack(alignment: .top) {
                VStack(spacing: 10) {
                    Button { confirmsFinish = true } label: {
                        Image(systemName: "stop.fill").foregroundStyle(.red).frame(width: 64, height: 64)
                            .overlay(Circle().stroke(.red, lineWidth: 1.5))
                    }.accessibilityLabel("러닝 종료")
                    Text("종료").font(.caption)
                }
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "pause.fill").font(.largeTitle).foregroundStyle(GrunnYStyle.brand.opacity(0.45))
                        .frame(width: 88, height: 88).background(GrunnYStyle.mint.opacity(0.5), in: Circle())
                    Text("일시정지 · 준비 중").font(.caption).foregroundStyle(GrunnYStyle.secondary)
                }.accessibilityElement(children: .combine)
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "lock").foregroundStyle(GrunnYStyle.secondary).frame(width: 64, height: 64)
                        .overlay(Circle().stroke(GrunnYStyle.border))
                    Text("잠금 · 준비 중").font(.caption).foregroundStyle(GrunnYStyle.secondary)
                }.accessibilityElement(children: .combine)
            }.padding(.top, 32)
        }.padding(20).padding(.bottom, 24)
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
                Rectangle().fill(GrunnYStyle.border).frame(width: 1, height: 56)
                stat("칼로리 · 미측정", value: "—")
            }.padding(20).background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 20) {
                Text("페이스 흐름").font(.subheadline).foregroundStyle(GrunnYStyle.brand)
                let points = pacePoints
                if points.count >= 2 {
                    Chart(points, id: \.date) { point in
                        LineMark(x: .value("시간", point.date), y: .value("분/km", point.pace / 60))
                            .foregroundStyle(GrunnYStyle.teal).lineStyle(.init(lineWidth: 3))
                    }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 170)
                } else {
                    Text("페이스를 표시할 GPS 기록이 부족해요.").font(.subheadline).foregroundStyle(GrunnYStyle.secondary)
                        .frame(maxWidth: .infinity, minHeight: 170)
                }
            }.padding(20).background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
            Text(location.message).font(.caption).foregroundStyle(GrunnYStyle.secondary)
            HStack(spacing: 12) {
                ShareLink(item: "GrunnY 러닝 · \(String(format: "%.2f", location.distance / 1000)) km · \(GrunnYStyle.elapsed(location.elapsedTime(at: now)))") {
                    Text("공유").font(.headline).frame(width: 92, height: 56).background(GrunnYStyle.soft, in: RoundedRectangle(cornerRadius: 16))
                }
                Button(action: done) { GrunnYPrimaryLabel(title: "완료") }.buttonStyle(.plain)
            }
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
