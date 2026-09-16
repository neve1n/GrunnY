//
//  ContentView.swift
//  GrunnY
//
//  Created by 최서진 on 9/16/26.
//

import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @State private var location = LocationManager()
    @State private var routePlanner = RoutePlanner()
    @State private var isChoosingDestination = false
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
    @AppStorage("targetDistanceKM") private var targetDistanceKM = 5.0
    @AppStorage("paceSecondsPerKM") private var paceSecondsPerKM = 330
    // 예약 시각은 앱을 다시 켤 때 과거 시각으로 남지 않도록 메모리에만 보관한다.
    @State private var departureTime: Date?
    @State private var showsRunSettings = false
    @State private var showsCrosswalks = false
    @State private var showsSignalComparison = false
    @State private var signalRows: [SeoulSignalRow] = []
    @State private var signalPlans: SeoulPlanCollection?
    @State private var draftDistance = 5.0
    @State private var draftPace = 330
    @State private var draftDepartsNow = true
    @State private var draftDeparture = Date()
    // 위치를 얻기 전에는 서울 지도를 표시한다.
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    ))

    var body: some View {
        MapReader { proxy in
        Map(position: $camera) {
            ForEach(Array(routePlanner.displayedLegs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(leg.polyline)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: [8, 5]))
            }
            if let destination = routePlanner.destination {
                Marker(routePlanner.targetMeters == nil ? "목적지" : "출발·도착", systemImage: "mappin", coordinate: destination)
                    .tint(.orange)
            }
            if location.runLocations.count >= 2 {
                MapPolyline(coordinates: location.runLocations.map(\.coordinate))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let start = location.runLocations.first {
                Marker("출발", systemImage: "flag.fill", coordinate: start.coordinate)
                    .tint(.green)
            }
            UserAnnotation()
            ForEach(Array(routePlanner.crosswalkMatches.prefix(80).enumerated()), id: \.element.id) { index, match in
                Annotation("횡단보도 후보 \(index + 1)", coordinate: match.crosswalk.coordinate) {
                    Text("\(index + 1)")
                        .font(.caption2.bold())
                        .padding(5)
                        .background(.background, in: Circle())
                        .overlay(Circle().stroke(.purple, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
        }
            .onTapGesture { position in
                guard isChoosingDestination,
                      let coordinate = proxy.convert(position, from: .local) else { return }
                camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            }
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .continuous) { context in
                mapCenter = context.region.center
            }
            .overlay {
                if isChoosingDestination {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                        .allowsHitTesting(false)
                        .accessibilityLabel("지도의 중심이 목적지가 됩니다")
                }
            }
            .safeAreaInset(edge: .top) { routePanel }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .bottom) {
                if !isChoosingDestination {
                VStack(alignment: .leading, spacing: 12) {
                    if !location.isRunning {
                        Button {
                            draftDistance = targetDistanceKM
                            draftPace = paceSecondsPerKM
                            draftDepartsNow = departureTime == nil
                            draftDeparture = departureTime ?? Date().addingTimeInterval(300)
                            showsRunSettings = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("코스 조건 설정", systemImage: "slider.horizontal.3")
                                Text("\(targetDistanceKM.formatted()) km · \(paceText(paceSecondsPerKM))/km")
                                    .font(.subheadline)
                                if let departureTime {
                                    Text("출발 \(departureTime.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                } else {
                                    Text("출발: 지금")
                                        .font(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .disabled(routePlanner.isLoading)
                    }
                    Text(location.message)
                        .font(.subheadline)
                    if location.runLocations.count >= 2 {
                        Label("달린 경로", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    if location.startedAt != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack {
                                Label(String(format: "%.2f km", location.distance / 1_000), systemImage: "figure.run")
                                Spacer()
                                let seconds = Int(location.elapsedTime(at: context.date))
                                Label(String(format: "%02d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60), systemImage: "timer")
                            }
                            .font(.headline)
                            .monospacedDigit()
                        }
                    }
                    if location.isRunning {
                        Button("러닝 종료", role: .destructive, action: location.endRun)
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                    } else {
                        Button("목표 거리로 순환 코스 찾기") {
                            Task {
                                await routePlanner.findLoops(from: location.currentLocation, targetKM: targetDistanceKM, pace: paceSecondsPerKM, departure: departureTime)
                                showEntireRoute()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(routePlanner.isLoading || !location.canStartRun)
                        Button("보행 경로 목적지 선택") {
                            routePlanner.clear()
                            isChoosingDestination = true
                            location.requestCurrentLocation()
                        }
                        .buttonStyle(.bordered)
                        .disabled(routePlanner.isLoading || !location.canStartRun)
                        Button(action: location.startRun) {
                            Text(location.startedAt == nil ? "러닝 시작" : "새 러닝 시작")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!location.canStartRun || routePlanner.isLoading)
                    }
                    if location.isDenied {
                        Button("설정에서 위치 권한 허용") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else if !location.isRunning {
                        Button(action: location.requestCurrentLocation) {
                            Label(location.isLocating ? "위치 확인 중…" : "현재 위치로 이동", systemImage: "location.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .disabled(location.isLocating || location.isRestricted || routePlanner.isLoading)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                }
            }
            .task {
                location.requestCurrentLocation()
            }
            .sheet(isPresented: $showsRunSettings) {
                runSettingsForm
            }
            .sheet(isPresented: $showsSignalComparison) {
                RouteComparisonView(assessments: routePlanner.signalAssessments(pace: paceSecondsPerKM, plans: signalPlans),
                                    pace: paceSecondsPerKM, departure: routePlanner.calculatedDeparture ?? .now,
                                    selectedIndex: routePlanner.selectedIndex, canSelect: !location.isRunning,
                                    target: targetDistanceKM * 1000,
                                    select: { routePlanner.selectCandidate($0); showEntireRoute() }, plans: $signalPlans)
            }
            .sheet(isPresented: $showsCrosswalks) {
                CrosswalkListView(matches: routePlanner.crosswalkMatches,
                                  dataAvailable: routePlanner.crosswalkDataAvailable, pace: paceSecondsPerKM,
                                  signalRows: $signalRows)
            }
            .onChange(of: location.currentLocation) { _, newLocation in
                // 러닝 중에는 사용자가 지도를 이동해도 GPS 갱신이 카메라를 빼앗지 않는다.
                guard !location.isRunning, !isChoosingDestination,
                      routePlanner.displayedLegs.isEmpty, !routePlanner.isLoading, let newLocation else { return }
                camera = .region(MKCoordinateRegion(
                    center: newLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }

    @ViewBuilder
    private var routePanel: some View {
        if isChoosingDestination || routePlanner.isLoading || !routePlanner.displayedLegs.isEmpty || routePlanner.message != nil {
            VStack(alignment: .leading, spacing: 8) {
                if isChoosingDestination {
                    Text("목적지를 탭하거나 지도를 움직여 중심 표시를 맞춰 주세요.")
                    HStack {
                        Button("취소") { isChoosingDestination = false }
                        Spacer()
                        Button("여기까지 보행 경로 찾기") {
                            let destination = mapCenter
                            isChoosingDestination = false
                            Task {
                                if let route = await routePlanner.findRoute(from: location.currentLocation, to: destination, departure: departureTime) {
                                    let rect = route.polyline.boundingMapRect
                                    camera = .rect(rect.insetBy(dx: -max(rect.width * 0.2, 200), dy: -max(rect.height * 0.2, 200)))
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if routePlanner.isLoading {
                    HStack {
                        ProgressView(routePlanner.progress)
                        Spacer()
                        Button("취소", action: routePlanner.clear)
                    }
                } else if !routePlanner.displayedLegs.isEmpty {
                    Label("\(routePlanner.selectedLoop == nil ? "보행 경로" : "순환 코스") · \((routePlanner.distance / 1_000).formatted(.number.precision(.fractionLength(2)))) km", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(.orange)
                    Text("예상 러닝 \(Int(ceil(routePlanner.distance / 1_000 * Double(paceSecondsPerKM) / 60)))분 · 신호 대기 미반영")
                        .font(.subheadline)
                    if let target = routePlanner.targetMeters {
                        Text("목표 \((target / 1_000).formatted()) km · 차이 \(Int((routePlanner.distance - target).rounded())) m · 거리 기준 선택")
                            .font(.caption)
                        if routePlanner.candidates.count > 1 && !location.isRunning {
                            Picker("순환 코스 후보", selection: Binding(get: { routePlanner.selectedIndex }, set: {
                                routePlanner.selectCandidate($0)
                                showEntireRoute()
                            })) {
                                ForEach(Array(routePlanner.candidates.enumerated()), id: \.element.id) { index, candidate in
                                    Text("\(index + 1) · \((candidate.distance / 1_000).formatted(.number.precision(.fractionLength(2)))) km").tag(index)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    } else {
                        Text("목적지까지 편도 경로 · 목표 거리 \(targetDistanceKM.formatted()) km")
                            .font(.caption)
                    }
                    if let message = routePlanner.message { Text(message).font(.caption) }
                    Button("코스별 신호 분석 · 계산 가능 여부 확인") { showsSignalComparison = true }
                    Button("횡단보도 후보 \(routePlanner.crosswalkMatches.count)곳 확인") { showsCrosswalks = true }
                    if routePlanner.crosswalkMatches.count > 80 {
                        Text("지도에는 첫 80곳 표시 · 전체는 목록에서 확인").font(.caption)
                    }
                    if !location.isRunning { Button("경로 지우기", action: routePlanner.clear) }
                } else if let message = routePlanner.message {
                    Text(message).font(.subheadline)
                    Button("닫기", action: routePlanner.clear)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
        }
    }

    private func showEntireRoute() {
        guard let rect = routePlanner.bounds else { return }
        camera = .rect(rect.insetBy(dx: -max(rect.width * 0.2, 200), dy: -max(rect.height * 0.2, 200)))
    }

    private func paceText(_ seconds: Int) -> String {
        String(format: "%d분 %02d초", seconds / 60, seconds % 60)
    }

    private var runSettingsForm: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let validDeparture = draftDepartsNow || draftDeparture > context.date
                Form {
                    Section {
                        NavigationLink("서울 보행신호 연결") {
                            SeoulSignalView(rows: $signalRows)
                        }
                        NavigationLink("서울 신호 운영계획") {
                            SeoulPlanView(result: $signalPlans, departure: departureTime ?? .now)
                        }
                    }
                    Section("목표 거리") {
                        Stepper(value: $draftDistance, in: 0.5...42, step: 0.5) {
                            Text("\(draftDistance.formatted()) km")
                        }
                        .accessibilityLabel("목표 거리")
                        .accessibilityValue("\(draftDistance.formatted()) 킬로미터")
                        Text("0.5~42 km · 0.5 km 단위")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("평균 러닝 페이스") {
                        Stepper(value: $draftPace, in: 180...900, step: 5) {
                            Text("\(paceText(draftPace)) / km")
                        }
                        .accessibilityLabel("평균 러닝 페이스")
                        .accessibilityValue("1킬로미터당 \(paceText(draftPace))")
                        Text("1 km를 달리는 시간 · 3~15분 · 5초 단위")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Toggle("지금 출발", isOn: $draftDepartsNow)
                        if !draftDepartsNow {
                            DatePicker("출발 날짜와 시각", selection: $draftDeparture, in: context.date..., displayedComponents: [.date, .hourAndMinute])
                            if !validDeparture {
                                Label("미래의 출발 시각을 선택해 주세요.", systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("출발 시각")
                    } footer: {
                        Text("‘지금’은 코스를 찾는 순간의 시각을 사용합니다. 지정 시각은 코스 계산용이며 러닝을 자동으로 시작하지 않습니다.")
                    }
                }
                .navigationTitle("코스 조건")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { showsRunSettings = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            guard (0.5...42).contains(draftDistance),
                                  (180...900).contains(draftPace),
                                  draftDepartsNow || draftDeparture > Date() else { return }
                            targetDistanceKM = draftDistance
                            paceSecondsPerKM = draftPace
                            departureTime = draftDepartsNow ? nil : draftDeparture
                            routePlanner.clear()
                            showsRunSettings = false
                        }
                        .disabled(!validDeparture)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
