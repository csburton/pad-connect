import ActivityKit
import Foundation
import PadKit

/// Shows the current walk as a Live Activity on the Lock Screen and in the
/// Dynamic Island. The app keeps running in the background while the pad is
/// connected, so it updates the activity directly; no push server is needed.
final class WalkActivityController {
    private var activity: Activity<WalkActivityAttributes>?
    private var lastState: WalkActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    /// The pad reports about once a second; the widget ticks the clock itself,
    /// so distance and speed only need refreshing every few seconds.
    static let minimumUpdateInterval: TimeInterval = 3

    init() {
        // A walk left over from a previous run (the app was killed mid-walk) is no longer live.
        for stale in Activity<WalkActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func start(_ tracker: WorkoutTracker, speedKmh: Double, heartRate: Int?) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Self.state(tracker, speedKmh: speedKmh, heartRate: heartRate)
        activity = try? Activity.request(attributes: WalkActivityAttributes(),
                                         content: ActivityContent(state: state, staleDate: nil))
        lastState = state
        lastUpdate = Date()
    }

    func update(_ tracker: WorkoutTracker, speedKmh: Double, heartRate: Int?) {
        guard let activity else { return }
        let state = Self.state(tracker, speedKmh: speedKmh, heartRate: heartRate)
        let beltChanged = state.isBeltRunning != lastState?.isBeltRunning
        guard state != lastState,
              beltChanged || Date().timeIntervalSince(lastUpdate) >= Self.minimumUpdateInterval
        else { return }
        lastState = state
        lastUpdate = Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Ends the activity. A finished walk stays on the Lock Screen for a few
    /// minutes as a summary; a discarded one disappears straight away.
    func end(_ tracker: WorkoutTracker, keepSummary: Bool) {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        var state = Self.state(tracker, speedKmh: 0, heartRate: nil)
        state.isFinished = true
        let policy: ActivityUIDismissalPolicy = keepSummary ? .after(Date().addingTimeInterval(5 * 60)) : .immediate
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy) }
    }

    private static func state(_ tracker: WorkoutTracker, speedKmh: Double,
                              heartRate: Int?) -> WalkActivityAttributes.ContentState {
        let moving = tracker.movingSeconds
        return WalkActivityAttributes.ContentState(
            movingSeconds: moving,
            // Rounded so that small timing jitter between samples doesn't count as a change.
            clockStart: speedKmh > 0 ? Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - moving).rounded()) : nil,
            speedKmh: speedKmh,
            distanceMeters: tracker.distanceMeters,
            heartRate: heartRate)
    }
}
