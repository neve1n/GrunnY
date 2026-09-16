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
    @AppStorage("targetDistanceKM") private var targetDistanceKM = 5.0
    @AppStorage("paceSecondsPerKM") private var paceSecondsPerKM = 330
    // 예약 시각은 앱을 다시 켤 때 과거 시각으로 남지 않도록 메모리에만 보관한다.
    @State private var departureTime: Date?
    @State private var showsRunSettings = false
    @State private var draftDistance = 5.0
    @State private var draftPace = 330
    @State private var draftDepartsNow = true
    @State private var draftDeparture = Date()
    // 위치를 얻기 전에는 대구 지도를 표시한다.
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.8714, longitude: 128.6014),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    ))

    var body: some View {
        Map(position: $camera) {
            if location.runLocations.count >= 2 {
                MapPolyline(coordinates: location.runLocations.map(\.coordinate))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let start = location.runLocations.first {
                Marker("출발", systemImage: "flag.fill", coordinate: start.coordinate)
                    .tint(.green)
            }
            UserAnnotation()
        }
            .mapStyle(.standard)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .safeAreaInset(edge: .bottom) {
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
                        Button(action: location.startRun) {
                            Text(location.startedAt == nil ? "러닝 시작" : "새 러닝 시작")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!location.canStartRun)
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
                        .disabled(location.isLocating || location.isRestricted)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
            }
            .task {
                location.requestCurrentLocation()
            }
            .sheet(isPresented: $showsRunSettings) {
                runSettingsForm
            }
            .onChange(of: location.currentLocation) { _, newLocation in
                // 러닝 중에는 사용자가 지도를 이동해도 GPS 갱신이 카메라를 빼앗지 않는다.
                guard !location.isRunning, let newLocation else { return }
                camera = .region(MKCoordinateRegion(
                    center: newLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
    }

    private func paceText(_ seconds: Int) -> String {
        String(format: "%d분 %02d초", seconds / 60, seconds % 60)
    }

    private var runSettingsForm: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let validDeparture = draftDepartsNow || draftDeparture > context.date
                Form {
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
