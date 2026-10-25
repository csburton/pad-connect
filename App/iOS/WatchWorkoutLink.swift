import HealthKit
import PadKit

/// The iPhone's side of a walk recorded on the Apple Watch.
///
/// When a walk starts the iPhone launches the Watch app with `startWatchApp`;
/// the Watch starts the workout and mirrors it back here. From then on the
/// iPhone streams pad data to the Watch, and the Watch saves the workout.
final class WatchWorkoutLink: NSObject, ObservableObject {
    @Published private(set) var isMirroring = false
    @Published private(set) var heartRate: Double?
    @Published private(set) var watchKcal: Double?

    /// A button pressed on the Watch.
    var onCommand: ((WatchMessage.Command) -> Void)?
    /// The Watch ended the walk itself (its own End button or a system stop).
    var onWatchEnded: (() -> Void)?

    private let store = HKHealthStore()
    private var mirrored: HKWorkoutSession?
    private var endRequestedByPhone = false

    override init() {
        super.init()
        // Must be set early: iOS can launch the app in the background to deliver it.
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            DispatchQueue.main.async { self?.attach(session) }
        }
    }

    /// Opens the Watch app and asks it to start an indoor walk. Does nothing
    /// useful (and fails quietly) when there's no paired Watch with the app.
    func startWatchWorkout() {
        guard HKHealthStore.isHealthDataAvailable(), !isMirroring else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .indoor
        store.startWatchApp(with: configuration) { _, _ in }
    }

    func send(_ message: WatchMessage) {
        guard let mirrored else { return }
        if message == .finish || message == .discard { endRequestedByPhone = true }
        mirrored.sendToRemoteWorkoutSession(data: message.encoded()) { _, _ in }
    }

    private func attach(_ session: HKWorkoutSession) {
        mirrored = session
        session.delegate = self
        endRequestedByPhone = false
        heartRate = nil
        watchKcal = nil
        isMirroring = true
    }

    private func detach() {
        let endedByWatch = isMirroring && !endRequestedByPhone
        mirrored = nil
        isMirroring = false
        heartRate = nil
        if endedByWatch { onWatchEnded?() }
    }

    private func handle(_ message: WatchMessage) {
        switch message {
        case .watchStats(let heart, let kcal):
            heartRate = heart
            watchKcal = kcal
        case .command(let command):
            onCommand?(command)
        case .padUpdate, .finish, .discard:
            break
        }
    }
}

extension WatchWorkoutLink: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        DispatchQueue.main.async { self.detach() }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.detach() }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap(WatchMessage.init(data:))
        DispatchQueue.main.async { messages.forEach(self.handle) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        // Lost touch, but the Watch may still be recording, so don't treat it as ended.
        DispatchQueue.main.async {
            self.mirrored = nil
            self.isMirroring = false
            self.heartRate = nil
        }
    }
}
