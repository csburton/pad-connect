import Foundation
import HealthKit
import PadKit

/// Runs the walk on the Watch: heart rate and calories come from the Watch,
/// speed and distance come from the pad via the iPhone.
///
/// The iPhone launches this through `startWatchApp`, the workout is mirrored
/// back to the iPhone, and the two talk over the mirrored session.
final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    enum Phase: Equatable {
        case idle
        case running
        case saving
        case saved
        case discarded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeKcal: Double = 0
    @Published private(set) var speedKmh: Double = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var isBeltRunning = false
    @Published private(set) var isConnectedToPhone = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var saveOnEnd = true

    /// Pad distance already written to the workout, and when.
    private var recordedDistance: Double = 0
    private var recordedDistanceDate: Date?
    private var lastStatsSent = Date.distantPast

    var startDate: Date? { builder?.startDate }

    func elapsedTime(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    // MARK: Authorization

    func requestAuthorization() {
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
        ]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        store.requestAuthorization(toShare: share, read: read) { _, _ in }
    }

    // MARK: Lifecycle

    func start(with configuration: HKWorkoutConfiguration) {
        guard session == nil else { return }
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            // Distance comes from the pad, not from wrist movement.
            dataSource.disableCollection(for: HKQuantityType(.distanceWalkingRunning))
            builder.dataSource = dataSource
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            resetStats()
            saveOnEnd = true
            phase = .running

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            session.startMirroringToCompanionDevice { [weak self] success, _ in
                DispatchQueue.main.async { self?.isConnectedToPhone = success }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Ends the workout. The iPhone hears about it through the mirrored session.
    func end(save: Bool) {
        guard let session, phase == .running else { return }
        saveOnEnd = save
        phase = save ? .saving : .discarded
        session.end()
    }

    func dismissSummary() {
        if phase != .running { phase = .idle }
    }

    // MARK: Talking to the iPhone

    func send(_ command: WatchMessage.Command) {
        send(.command(command))
    }

    private func send(_ message: WatchMessage) {
        session?.sendToRemoteWorkoutSession(data: message.encoded()) { _, _ in }
    }

    private func handle(_ message: WatchMessage) {
        switch message {
        case .padUpdate(let speed, let distance, let running):
            speedKmh = speed
            isBeltRunning = running
            distanceMeters = distance
            recordDistance(upTo: distance)
        case .finish:
            end(save: true)
        case .discard:
            end(save: false)
        case .watchStats, .command:
            break
        }
    }

    private func recordDistance(upTo total: Double) {
        let now = Date()
        let start = recordedDistanceDate ?? builder?.startDate ?? now
        let delta = total - recordedDistance
        // Batch into samples of at least 10 m or 30 s so Health isn't flooded.
        guard let builder, delta > 0, delta >= 10 || now.timeIntervalSince(start) >= 30, now > start else { return }
        let sample = HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning),
                                      quantity: HKQuantity(unit: .meter(), doubleValue: delta),
                                      start: start, end: now)
        recordedDistance = total
        recordedDistanceDate = now
        builder.add([sample]) { _, _ in }
    }

    private func resetStats() {
        heartRate = nil
        activeKcal = 0
        speedKmh = 0
        distanceMeters = 0
        isBeltRunning = false
        recordedDistance = 0
        recordedDistanceDate = nil
        lastStatsSent = .distantPast
    }

    private func finishCollection(at date: Date) {
        guard let builder else { return }
        // Write the last bit of distance before closing the workout.
        let remaining = distanceMeters - recordedDistance
        if saveOnEnd, remaining > 0, let start = recordedDistanceDate ?? builder.startDate, date > start {
            builder.add([HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning),
                                          quantity: HKQuantity(unit: .meter(), doubleValue: remaining),
                                          start: start, end: date)]) { _, _ in }
        }
        builder.endCollection(withEnd: date) { [weak self] _, _ in
            guard let self else { return }
            if self.saveOnEnd {
                builder.addMetadata([HKMetadataKeyIndoorWorkout: true]) { _, _ in
                    builder.finishWorkout { workout, error in
                        DispatchQueue.main.async {
                            self.phase = workout != nil ? .saved : .failed(error?.localizedDescription ?? "Couldn't save the walk.")
                            self.cleanUp()
                        }
                    }
                }
            } else {
                builder.discardWorkout()
                DispatchQueue.main.async { self.cleanUp() }
            }
        }
    }

    private func cleanUp() {
        session = nil
        builder = nil
        isConnectedToPhone = false
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        DispatchQueue.main.async {
            // Ended from the Watch's own controls or by the system: save what we have.
            if self.phase == .running { self.phase = .saving }
            self.finishCollection(at: date)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.phase = .failed(error.localizedDescription) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap(WatchMessage.init(data:))
        DispatchQueue.main.async { messages.forEach(self.handle) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        DispatchQueue.main.async { self.isConnectedToPhone = false }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?.doubleValue(for: bpm)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        DispatchQueue.main.async {
            if let heart { self.heartRate = heart }
            if let kcal { self.activeKcal = kcal }
            // A few updates a second is more than the iPhone needs.
            if Date().timeIntervalSince(self.lastStatsSent) >= 2 {
                self.lastStatsSent = Date()
                self.send(.watchStats(heartRate: self.heartRate, activeKcal: self.activeKcal))
            }
        }
    }
}
