import CoreLocation
import MapKit
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
    let guidance = RunGuidance()
    private var announcements = RunAnnouncements()
    private var targetDistance: Double?
    private var targetPace: Int?
    private var plannedDistance: Double?
    private var plannedDuration: Double?
    private var runID = UUID()
    private(set) var saveError: String?
    private var completedRecord: RunRecord?

    func prepareRun(routes: [MKRoute], targetDistance: Double?, targetPace: Int, estimatedWait: Double?) {
        guidance.configure(routes: routes)
        guidance.emit = { text in
            let event = text.contains("코스에서") || text.contains("코스로 돌아왔어요") || text.contains("경로 안내를 종료")
            RunVoice.shared.say(text, priority: event ? .event : .direction)
        }
        guidance.cancelDirections = { RunVoice.shared.cancelDirections() }
        self.targetDistance = targetDistance
        self.targetPace = targetPace
        let meters = routes.reduce(0) { $0 + $1.distance }
        plannedDistance = meters.isFinite && meters > 0 ? meters : nil
        if let estimatedWait, estimatedWait.isFinite, estimatedWait >= 0, let plannedDistance {
            plannedDuration = plannedDistance / 1000 * Double(targetPace) + estimatedWait
        } else { plannedDuration = nil }
    }

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
        announcements = RunAnnouncements()
        runID = UUID(); saveError = nil; completedRecord = nil
        runLocations.removeAll()
        distance = 0
        startedAt = Date()
        endedAt = nil
        isRunning = true
        isLocating = false
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        message = "러닝 중 · GPS 위치를 기다리고 있습니다."
        manager.startUpdatingLocation()
    }

    enum FinishReason: String { case manual, arrival, interrupted }

    func endRun(reason: FinishReason = .manual) {
        guard isRunning, let startedAt else { return }
        isRunning = false
        let ended = Date()
        endedAt = ended
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.distanceFilter = kCLDistanceFilterNone
        isLocating = false
        let latest = runLocations.last
        let freshArrival = latest.map {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 35
                && abs(ended.timeIntervalSince($0.timestamp)) <= 15
        } ?? false
        let evidence = RunCompletionEvidence(gpsArrived: reason == .arrival && guidance.arrived && freshArrival,
            actualDistance: distance, actualDuration: max(0, ended.timeIntervalSince(startedAt)),
            plannedDistance: plannedDistance, plannedDuration: plannedDuration,
            distanceTolerance: 0.05, timeTolerance: 0.10)
        completedRecord = RunRecord(id: runID, startedAt: startedAt, endedAt: ended,
            distance: distance, targetDistance: targetDistance, targetPace: targetPace,
            finishReason: reason.rawValue, missionComplete: reason == .arrival && evidence.missionComplete,
            points: runLocations.map { .init(latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude, timestamp: $0.timestamp) })
        saveCompletedRun()
        RunVoice.shared.stop()
        switch reason {
        case .manual:
            RunVoice.shared.say(saveError == nil ? "러닝을 종료했어요. 지금까지의 기록을 저장할게요."
                : "러닝을 종료했어요. 기록을 저장하지 못했어요. 화면을 확인해 주세요.", priority: .event)
        case .arrival: RunVoice.shared.say(evidence.announcement, priority: .event)
        case .interrupted: RunVoice.shared.say("위치 정보를 확인할 수 없어 러닝을 중단했어요.", priority: .event)
        }
        message = "러닝을 종료했습니다."
    }

    func saveCompletedRun() {
        guard let completedRecord else { return }
        do { try completedRecord.save(); saveError = nil }
        catch { saveError = "기록을 저장하지 못했어요. 다시 시도해 주세요." }
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
            endRun(reason: .interrupted)
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
                    let delta = point.distance(from: previous)
                    let seconds = point.timestamp.timeIntervalSince(previous.timestamp)
                    // Reject GPS jumps rather than inventing kilometre splits/arrival.
                    guard seconds > 0, delta / seconds <= 10 else { continue }
                    distance += delta
                }
                runLocations.append(point)
                currentLocation = point
                guidance.update(location: point, now: .now, traveled: distance)
                let lines = announcements.update(distance: distance,
                    elapsed: max(0, point.timestamp.timeIntervalSince(startedAt)),
                    target: targetDistance, arrived: guidance.arrived)
                if guidance.arrived { endRun(reason: .arrival); break }
                for line in lines { RunVoice.shared.say(line, priority: .record, lifetime: 90) }
            }
            guard isRunning else { return }
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
        message = "현재 위치를 확인했습니다."
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            endRun(reason: .interrupted)
            authorization = manager.authorizationStatus
            showPermissionStatus()
        } else if isRunning, (error as? CLError)?.code == .locationUnknown {
            message = "GPS 신호가 약합니다. 위치 수신을 기다리고 있습니다."
        } else {
            let wasRunning = isRunning
            endRun(reason: .interrupted)
            message = "위치를 확인할 수 없습니다. 기기의 위치 서비스를 확인한 뒤 다시 시도해 주세요."
            if wasRunning { message = "위치 오류로 러닝 기록을 중단했습니다. 위치 서비스를 확인해 주세요." }
        }
    }

    private func showPermissionStatus() {
        isLocating = false
        message = isRestricted
            ? "기기에서 위치 사용이 제한되어 있습니다. 지도를 둘러볼 수 있습니다."
            : "위치 권한이 꺼져 있습니다. 설정에서 허용하면 현재 위치를 표시합니다."
    }
}
