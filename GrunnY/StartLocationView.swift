import SwiftUI
import MapKit
import Observation

struct RunStartPoint {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

@MainActor @Observable
final class StartPlaceSearch {
    private(set) var results: [MKMapItem] = []
    private(set) var isSearching = false
    private(set) var message: String?
    private var task: Task<Void, Never>?
    private var request: MKLocalSearch?
    private var generation = UUID()
    private var activeQuery: String?

    func cancel() {
        generation = UUID()
        task?.cancel()
        request?.cancel()
        task = nil
        request = nil
        isSearching = false
        results = []
        message = nil
        activeQuery = nil
    }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Submitting an already displayed query must not clear its tappable results.
        guard query != activeQuery else { return }
        cancel()
        guard !query.isEmpty else { return }
        activeQuery = query
        let token = generation
        isSearching = true
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(450))
                try Task.checkCancellation()
                let configuration = MKLocalSearch.Request()
                configuration.naturalLanguageQuery = query
                configuration.region = MKCoordinateRegion(
                    center: .init(latitude: 37.5665, longitude: 126.9780),
                    span: .init(latitudeDelta: 0.38, longitudeDelta: 0.60))
                configuration.resultTypes = [.address, .pointOfInterest]
                let search = MKLocalSearch(request: configuration)
                request = search
                let response = try await search.start()
                try Task.checkCancellation()
                guard generation == token else { return }
                // A search region is only a hint; verify the administrative area
                // so nearby places in Gyeonggi-do cannot enter the results.
                results = response.mapItems.filter {
                    let place = $0.placemark
                    let area = place.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return CLLocationCoordinate2DIsValid($0.location.coordinate)
                        && place.isoCountryCode == "KR"
                        && ["서울", "서울특별시", "seoul", "seoul special city"].contains(area ?? "")
                }
                message = results.isEmpty ? "서울 내 검색 결과가 없어요. 서울의 장소명이나 주소로 검색해 주세요." : nil
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                activeQuery = nil
                message = "장소를 찾지 못했어요. 검색어와 네트워크를 확인해 주세요."
            }
            guard generation == token else { return }
            isSearching = false
            task = nil
            request = nil
        }
    }
}

struct StartLocationView: View {
    let location: LocationManager
    @Binding var selection: RunStartPoint?
    let next: () -> Void
    @State private var showsAppInfo = false
    @State private var search = StartPlaceSearch()
    @State private var query = ""
    @State private var showsResults = false
    @State private var camera: MapCameraPosition = .region(Self.initialRegion)
    @State private var wantsCurrentLocation = false
    @State private var locationMessage: String?
    @State private var addressTask: Task<Void, Never>?
    @State private var addressRequest: MKReverseGeocodingRequest?
    @State private var addressGeneration = UUID()
    @FocusState private var isSearching: Bool
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .title) private var titleSize = 28.0

    private static let initialRegion = MKCoordinateRegion(
        center: .init(latitude: 37.5665, longitude: 126.9780),
        span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025))

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("GrunnY").font(.title3.bold()).foregroundStyle(GrunnYStyle.brand)
                        Spacer()
                        Button { showsAppInfo = true } label: {
                            Image(systemName: "info.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("앱 정보 및 러닝 기록")
                    }.frame(height: 44)
                    .sheet(isPresented: $showsAppInfo) { AppInfoView() }
                    Text("어디서\n출발할까요?")
                        .font(.system(size: titleSize, weight: .bold)).lineSpacing(2)
                    VStack(alignment: .leading, spacing: 16) {
                        searchField
                        if showsResults, let message = search.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(GrunnYStyle.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 4)
                        }
                    }
                    if showsResults {
                        searchResults
                    } else {
                        map.frame(height: max(240, geometry.size.height - 240))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    if let locationMessage {
                        Text(locationMessage).font(.footnote).foregroundStyle(GrunnYStyle.secondary)
                        if location.isDenied {
                            Button("위치 권한 설정 열기") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }.font(.footnote).frame(minHeight: 44)
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(GrunnYStyle.background)
        .safeAreaInset(edge: .bottom) {
            Button {
                guard selection != nil else { return }
                isSearching = false
                search.cancel()
                next()
            } label: { GrunnYPrimaryLabel(title: "다음") }
                .buttonStyle(.plain).disabled(selection == nil || wantsCurrentLocation || showsResults)
                .opacity(selection == nil || wantsCurrentLocation || showsResults ? 0.45 : 1)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(GrunnYStyle.background)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: isSearching) { _, focused in
            if focused {
                cancelAddressLookup()
                showsResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                search.search(query)
            }
        }
        .onChange(of: location.currentLocation) { _, point in
            guard wantsCurrentLocation, let point, isFresh(point) else { return }
            choose(name: "현재 위치", coordinate: point.coordinate)
        }
        .onChange(of: location.isLocating) { _, locating in
            guard wantsCurrentLocation, !locating else { return }
            if let point = location.currentLocation, isFresh(point) {
                choose(name: "현재 위치", coordinate: point.coordinate)
            } else {
                wantsCurrentLocation = false
                locationMessage = location.message
            }
        }
        .onAppear {
            if let selection { center(on: selection.coordinate) }
            else { query = "" }
        }
        .onDisappear { search.cancel(); cancelAddressLookup(); wantsCurrentLocation = false }
    }

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass").foregroundStyle(GrunnYStyle.secondary)
            TextField("서울의 장소를 검색해보세요", text: Binding(
                get: { query },
                set: { value in
                    guard value != query else { return }
                    query = value
                    showsResults = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    search.search(value)
                }))
                .font(.body).focused($isSearching).submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    guard showsResults else { return }
                    showsResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    search.search(query)
                }
            if !query.isEmpty {
                Button {
                    cancelAddressLookup()
                    query = ""
                    showsResults = false
                    search.cancel()
                } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel("검색어 지우기")
            }
        }.padding(.horizontal, 16).frame(minHeight: 48)
            .background(GrunnYStyle.control, in: RoundedRectangle(cornerRadius: 14))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            if search.isSearching {
                ProgressView()
                    .accessibilityLabel("장소 찾는 중")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }
            ForEach(Array(search.results.prefix(10).enumerated()), id: \.offset) { _, item in
                Button {
                    choose(name: item.name ?? "선택한 장소", coordinate: item.location.coordinate)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle").foregroundStyle(GrunnYStyle.brand)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "장소").font(.body.weight(.medium))
                            if let address = item.address?.fullAddress {
                                Text(address).font(.caption).foregroundStyle(GrunnYStyle.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(.vertical, 8)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if location.authorization == .authorizedAlways || location.authorization == .authorizedWhenInUse {
                    UserAnnotation()
                }
                if let selection {
                    Annotation(selection.name, coordinate: selection.coordinate, anchor: .center) {
                        ZStack {
                            Circle().fill(GrunnYStyle.teal).frame(width: 14, height: 14)
                                .padding(5).background(.white, in: Circle())
                                .overlay(Circle().stroke(GrunnYStyle.brand, lineWidth: 3))
                            Text(selection.name)
                                .font(.caption.weight(.semibold)).foregroundStyle(GrunnYStyle.brand)
                                .lineLimit(2).padding(.horizontal, 16).padding(.vertical, 8)
                                .background(.white, in: Capsule())
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 3)
                                .offset(y: 38)
                        }.accessibilityLabel("출발지: \(selection.name)")
                    }.annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                chooseMapLocation(coordinate)
            }
            .overlay(alignment: .top) {
                if selection == nil {
                    Text("장소를 검색하거나 지도를 눌러 출발지를 정해 주세요")
                        .font(.caption).padding(10).background(.regularMaterial, in: Capsule()).padding(12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: useCurrentLocation) {
                    ZStack {
                        Circle().strokeBorder(lineWidth: 2.5)
                        ForEach(0..<4) { index in
                            Rectangle().frame(width: 2.5, height: 5)
                                .offset(y: -8.5)
                                .rotationEffect(.degrees(Double(index) * 90))
                        }
                    }
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Color(white: 0.26))
                    .frame(width: 48, height: 48)
                    .background {
                        Circle().fill(LinearGradient(
                            colors: [Color(white: 0.89), Color(white: 0.96)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .contentShape(Circle())
                }.buttonStyle(.plain).padding(16).accessibilityLabel("현재 위치를 출발지로 선택")
            }
        }
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        camera = .region(.init(center: coordinate, span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)))
    }
    private func choose(name: String, coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        cancelAddressLookup()
        selection = RunStartPoint(name: name, coordinate: coordinate)
        wantsCurrentLocation = false
        locationMessage = nil
        isSearching = false
        showsResults = false
        query = name
        search.cancel()
        center(on: coordinate)
    }
    private func cancelAddressLookup() {
        if locationMessage == "주소 확인 중…" { locationMessage = nil }
        addressGeneration = UUID()
        addressTask?.cancel()
        addressRequest?.cancel()
        addressTask = nil
        addressRequest = nil
    }

    private func chooseMapLocation(_ coordinate: CLLocationCoordinate2D) {
        choose(name: "출발지", coordinate: coordinate)
        query = ""
        locationMessage = "주소 확인 중…"
        let token = addressGeneration
        addressTask = Task { @MainActor in
            defer {
                if addressGeneration == token {
                    addressTask = nil
                    addressRequest = nil
                }
            }
            do {
                // Debounce repeated map taps and never replace the tapped coordinate
                // with the nearby address's representative coordinate.
                try await Task.sleep(for: .milliseconds(350))
                guard let request = MKReverseGeocodingRequest(location: CLLocation(
                    latitude: coordinate.latitude, longitude: coordinate.longitude)) else {
                    throw URLError(.badURL)
                }
                request.preferredLocale = Locale(identifier: "ko_KR")
                addressRequest = request
                let items = try await request.mapItems
                try Task.checkCancellation()
                guard addressGeneration == token else { return }
                let name = items.first.flatMap { item in
                    [item.name, item.address?.fullAddress]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty }
                }
                guard let name else { throw URLError(.cannotParseResponse) }
                selection = RunStartPoint(name: name, coordinate: coordinate)
                query = name
                locationMessage = nil
            } catch {
                guard !Task.isCancelled, addressGeneration == token else { return }
                locationMessage = "이 위치의 주소를 확인하지 못했어요. 지도를 다시 누르거나 장소명으로 검색해 주세요."
            }
        }
    }
    private func isFresh(_ point: CLLocation) -> Bool {
        point.horizontalAccuracy >= 0 && abs(point.timestamp.timeIntervalSinceNow) < 60
    }
    private func useCurrentLocation() {
        cancelAddressLookup()
        isSearching = false
        showsResults = false
        search.cancel()
        if let point = location.currentLocation, isFresh(point) {
            choose(name: "현재 위치", coordinate: point.coordinate)
            return
        }
        wantsCurrentLocation = true
        locationMessage = nil
        location.requestCurrentLocation()
        if !location.isLocating {
            wantsCurrentLocation = false
            locationMessage = location.message
        }
    }
}
