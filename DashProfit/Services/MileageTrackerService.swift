import CoreLocation
import Foundation
import Observation
#if canImport(ActivityKit)
import ActivityKit
#endif

struct LoggedShift: Codable, Identifiable, Equatable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let miles: Double
    let vehicleCost: Double
    let taxDeduction: Double
}

struct LiveShiftDraft: Codable, Equatable {
    let dateKey: String
    let startTime: Date
    var shiftMiles: Double
    var updatedAt: Date
    var isShiftTiming: Bool
    var shiftStartedAt: Date?
}

@Observable
final class MileageTrackerService: NSObject, CLLocationManagerDelegate {
    var isTracking = false
    var shiftMiles: Double = 0.0
    var tripMiles: Double = 0.0
    var elapsedSeconds: Int = 0
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var errorMessage: String?

    // Independent shift clock (can run with or without GPS; auto-starts with GPS)
    var isShiftTiming = false
    var liveShiftElapsedSeconds: Int = 0

    private let manager = CLLocationManager()
    private var lastValidLocation: CLLocation?
    private var shiftStartTime: Date?
    private var shiftClockStartTime: Date?
    private var timer: Timer?
    private var lastDraftSavedAt: Date?
    private static let draftKey = "dashprofit_ios_live_shift_draft_v1"

    #if canImport(ActivityKit)
    private var liveActivity: Activity<DashShiftActivityAttributes>?
    #endif

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 15
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - GPS Segment Validation (pure & testable)

    /// Accepts segments after dropouts/tunnels as long as implied speed is <= 100 mph.
    static func isValidSegment(
        deltaMeters: Double,
        deltaSeconds: TimeInterval,
        horizontalAccuracy: Double
    ) -> Bool {
        guard horizontalAccuracy >= 0, horizontalAccuracy <= 65 else { return false }
        guard deltaMeters >= 8.0 else { return false }
        if deltaSeconds > 0 {
            let miles = deltaMeters / 1609.344
            let hours = deltaSeconds / 3600.0
            let mph = miles / hours
            return mph <= 100.0
        }
        return deltaMeters <= 400.0
    }

    // MARK: - Shift Timer

    func toggleShiftTimer(onSaveElapsed: ((Int) -> Void)? = nil) {
        if isShiftTiming {
            stopShiftTimer(onSaveElapsed: onSaveElapsed)
        } else {
            startShiftTimer()
        }
    }

    func startShiftTimer() {
        guard !isShiftTiming else { return }
        isShiftTiming = true
        shiftClockStartTime = Date()
        liveShiftElapsedSeconds = 0
        ensureTimerRunning()
        saveDraftNow()
    }

    func stopShiftTimer(onSaveElapsed: ((Int) -> Void)? = nil) {
        guard isShiftTiming else { return }
        let elapsed = shiftClockStartTime.map { max(0, Int(Date().timeIntervalSince($0))) } ?? liveShiftElapsedSeconds
        isShiftTiming = false
        shiftClockStartTime = nil
        liveShiftElapsedSeconds = 0
        if !isTracking {
            timer?.invalidate()
            timer = nil
        }
        onSaveElapsed?(elapsed)
        saveDraftNow()
    }

    func formattedShiftTimer(savedSeconds: Int) -> String {
        let total = max(0, savedSeconds + (isShiftTiming ? liveShiftElapsedSeconds : 0))
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - GPS Shift Tracking

    func toggleShift(onStop: ((LoggedShift) -> Void)? = nil) {
        if isTracking {
            stopShift(onStop: onStop)
        } else {
            startShift()
        }
    }

    func startShift() {
        errorMessage = nil
        let status = manager.authorizationStatus
        authorizationStatus = status

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }

        if status == .denied || status == .restricted {
            errorMessage = "Location permission is disabled. Enable it in iPhone Settings → DashProfit."
            return
        }

        if status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }

        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()

        isTracking = true
        shiftMiles = 0.0
        tripMiles = 0.0
        elapsedSeconds = 0
        lastValidLocation = nil
        shiftStartTime = Date()
        lastDraftSavedAt = Date()

        if !isShiftTiming {
            startShiftTimer()
        }

        ensureTimerRunning()
        saveDraftNow()
        startLiveActivityIfAvailable()
    }

    func stopShift(onStop: ((LoggedShift) -> Void)? = nil) {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
        if !isShiftTiming {
            timer?.invalidate()
            timer = nil
        }

        if let start = shiftStartTime, shiftMiles >= 0.05 {
            let settings = DashSettings.load()
            let shift = LoggedShift(
                id: UUID(),
                startTime: start,
                endTime: Date(),
                miles: shiftMiles,
                vehicleCost: shiftMiles * settings.costPerMile,
                taxDeduction: shiftMiles * settings.irsRate
            )
            onStop?(shift)
        }
        shiftStartTime = nil
        clearDraftIfIdle()
        endLiveActivityIfAvailable()
    }

    func resetTripMiles() {
        tripMiles = 0.0
    }

    var formattedElapsed: String {
        let hrs = elapsedSeconds / 3600
        let mins = (elapsedSeconds % 3600) / 60
        let secs = elapsedSeconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    private func ensureTimerRunning() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            if self.isTracking, let start = self.shiftStartTime {
                self.elapsedSeconds = Int(now.timeIntervalSince(start))
            }
            if self.isShiftTiming, let cStart = self.shiftClockStartTime {
                self.liveShiftElapsedSeconds = Int(now.timeIntervalSince(cStart))
            }
            if self.isTracking || self.isShiftTiming {
                if let lastSaved = self.lastDraftSavedAt {
                    if now.timeIntervalSince(lastSaved) >= 15.0 {
                        self.saveDraftNow()
                    }
                } else {
                    self.saveDraftNow()
                }
            }
        }
    }

    // MARK: - Incremental Draft Persistence & Crash Recovery

    func saveDraftNow() {
        guard isTracking || isShiftTiming else {
            UserDefaults.standard.removeObject(forKey: Self.draftKey)
            return
        }
        let now = Date()
        let draft = LiveShiftDraft(
            dateKey: OfferCalculator.localDateKey(for: now),
            startTime: shiftStartTime ?? now,
            shiftMiles: shiftMiles,
            updatedAt: now,
            isShiftTiming: isShiftTiming,
            shiftStartedAt: shiftClockStartTime
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: Self.draftKey)
        }
        lastDraftSavedAt = now
    }

    private func clearDraftIfIdle() {
        if !isTracking && !isShiftTiming {
            UserDefaults.standard.removeObject(forKey: Self.draftKey)
        } else {
            saveDraftNow()
        }
    }

    static func consumeRecoveredDraft(settings: DashSettings) -> (shift: LoggedShift?, dateKey: String, extraShiftSeconds: Int)? {
        guard let data = UserDefaults.standard.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(LiveShiftDraft.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: draftKey)

        let recoveredShift: LoggedShift?
        if draft.shiftMiles >= 0.05 {
            recoveredShift = LoggedShift(
                id: UUID(),
                startTime: draft.startTime,
                endTime: draft.updatedAt,
                miles: draft.shiftMiles,
                vehicleCost: draft.shiftMiles * settings.costPerMile,
                taxDeduction: draft.shiftMiles * settings.irsRate
            )
        } else {
            recoveredShift = nil
        }

        let extraSecs: Int
        if draft.isShiftTiming, let startedAt = draft.shiftStartedAt {
            extraSecs = max(0, Int(draft.updatedAt.timeIntervalSince(startedAt)))
        } else {
            extraSecs = 0
        }

        if recoveredShift == nil && extraSecs == 0 {
            return nil
        }
        return (recoveredShift, draft.dateKey, extraSecs)
    }

    // MARK: - Live Activity (ActivityKit)

    func updateLiveActivity(summary: DailySummary) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let activity = liveActivity else { return }
        let state = DashShiftActivityAttributes.ContentState(
            milesToday: summary.totalMiles,
            taxWriteOff: summary.taxDeduction,
            netProfit: summary.netProfit,
            elapsedSeconds: elapsedSeconds
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        #endif
    }

    private func startLiveActivityIfAvailable() {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let settings = DashSettings.load()
        let attrs = DashShiftActivityAttributes(irsRate: settings.irsRate)
        let state = DashShiftActivityAttributes.ContentState(
            milesToday: shiftMiles,
            taxWriteOff: shiftMiles * settings.irsRate,
            netProfit: 0,
            elapsedSeconds: 0
        )
        liveActivity = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        #endif
    }

    private func endLiveActivityIfAvailable() {
        #if canImport(ActivityKit)
        guard let activity = liveActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        liveActivity = nil
        #endif
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if !isTracking && (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways) {
            errorMessage = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking else { return }
        for loc in locations {
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 65 else { continue }
            if let last = lastValidLocation {
                let deltaMeters = loc.distance(from: last)
                let deltaSeconds = loc.timestamp.timeIntervalSince(last.timestamp)
                if Self.isValidSegment(
                    deltaMeters: deltaMeters,
                    deltaSeconds: deltaSeconds,
                    horizontalAccuracy: loc.horizontalAccuracy
                ) {
                    let deltaMiles = deltaMeters / 1609.344
                    shiftMiles += deltaMiles
                    tripMiles += deltaMiles
                    lastValidLocation = loc
                }
            } else {
                lastValidLocation = loc
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "GPS error: \(error.localizedDescription)"
    }
}
