import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var currentLocation: CLLocation?
    private(set) var isLocating = false
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var message = "코스의 출발점을 찾기 위해 현재 위치를 확인합니다."
    private(set) var isRunning = false
    private(set) var runLocations: [CLLocation] = []
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var distance: CLLocationDistance = 0

    var isDenied: Bool { authorization == .denied }
    var isRestricted: Bool { authorization == .restricted }
    var canStartRun: Bool {
        !isRunning && (authorization == .authorizedWhenInUse || authorization == .authorizedAlways)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        authorization = manager.authorizationStatus
    }

    func requestCurrentLocation() {
        guard !isLocating, !isRunning else { return }
        isLocating = true
        message = "현재 위치를 확인하고 있습니다."
        authorization = manager.authorizationStatus
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            showPermissionStatus()
        }
    }

    func startRun() {
        guard canStartRun else { return }
        manager.stopUpdatingLocation()
        runLocations.removeAll()
        distance = 0
        startedAt = Date()
        endedAt = nil
        isRunning = true
        isLocating = false
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        message = "러닝 중 · GPS 위치를 기다리고 있습니다."
        manager.startUpdatingLocation()
    }

    func endRun() {
        guard isRunning else { return }
        isRunning = false
        endedAt = Date()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.distanceFilter = kCLDistanceFilterNone
        isLocating = false
        message = "러닝을 종료했습니다."
    }

    func elapsedTime(at date: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (endedAt ?? date).timeIntervalSince(startedAt))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !isRunning else { return }
            // 설정에서 권한을 허용하고 돌아온 경우에도 위치를 다시 얻는다.
            isLocating = true
            message = "현재 위치를 확인하고 있습니다."
            manager.requestLocation()
        case .denied, .restricted:
            endRun()
            currentLocation = nil
            showPermissionStatus()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if isRunning, let startedAt {
            for point in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                // 시작 전 캐시, 부정확한 위치, 중복/역순 위치는 기록하지 않는다.
                guard point.horizontalAccuracy >= 0, point.horizontalAccuracy <= 50,
                      point.timestamp >= startedAt,
                      abs(point.timestamp.timeIntervalSinceNow) < 30 else { continue }
                if let previous = runLocations.last {
                    guard point.timestamp > previous.timestamp else { continue }
                    distance += point.distance(from: previous)
                }
                runLocations.append(point)
                currentLocation = point
            }
            message = runLocations.isEmpty
                ? "러닝 중 · 정확한 GPS 위치를 기다리고 있습니다."
                : "러닝 중 · 이동 경로를 기록하고 있습니다."
            return
        }
        // 종료 후 늦게 도착한 콜백은 러닝 결과와 안내를 변경하지 않는다.
        guard isLocating else { return }
        guard let latest = locations.last,
              latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 60 else {
            isLocating = false
            message = "최근 위치를 얻지 못했습니다. 현재 위치를 다시 확인해 주세요."
            return
        }
        currentLocation = latest
        isLocating = false
        message = "현재 위치를 확인했습니다. 코스 지원 지역은 대구입니다."
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            endRun()
            authorization = manager.authorizationStatus
            showPermissionStatus()
        } else if isRunning, (error as? CLError)?.code == .locationUnknown {
            message = "GPS 신호가 약합니다. 위치 수신을 기다리고 있습니다."
        } else {
            let wasRunning = isRunning
            endRun()
            message = "위치를 확인할 수 없습니다. 기기의 위치 서비스를 확인한 뒤 다시 시도해 주세요."
            if wasRunning { message = "위치 오류로 러닝 기록을 중단했습니다. 위치 서비스를 확인해 주세요." }
        }
    }

    private func showPermissionStatus() {
        isLocating = false
        message = isRestricted
            ? "기기에서 위치 사용이 제한되어 있습니다. 대구 지도를 둘러볼 수 있습니다."
            : "위치 권한이 꺼져 있습니다. 설정에서 허용하면 현재 위치를 표시합니다."
    }
}
