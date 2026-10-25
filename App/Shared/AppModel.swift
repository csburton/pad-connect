import Foundation
import PadKit

/// Owns the pad connection and the current walk, and saves finished walks.
final class AppModel: ObservableObject {
    let pad = TreadmillController()

    @Published private(set) var tracker: WorkoutTracker
    @Published private(set) var isSessionActive = false
    @Published var saveMessage: String?

    @Published var bodyMassKg: Double {
        didSet {
            UserDefaults.standard.set(bodyMassKg, forKey: "bodyMassKg")
            tracker.bodyMassKg = bodyMassKg
        }
    }

    @Published var speedStepKmh: Double {
        didSet { UserDefaults.standard.set(speedStepKmh, forKey: "speedStepKmh") }
    }

    /// Finish the walk automatically after the belt has been stopped this long.
    static let autoFinishAfter: TimeInterval = 5 * 60

    #if os(iOS)
    private let health = HealthWriter()
    let watch = WatchWorkoutLink()
    private let liveActivity = WalkActivityController()
    #endif

    init() {
        let defaults = UserDefaults.standard
        let mass = defaults.object(forKey: "bodyMassKg") as? Double ?? 75
        bodyMassKg = mass
        speedStepKmh = defaults.object(forKey: "speedStepKmh") as? Double ?? 0.5
        tracker = WorkoutTracker(bodyMassKg: mass)
        pad.onSample = { [weak self] sample in self?.handle(sample) }
        #if os(iOS)
        watch.onCommand = { [weak self] command in self?.handle(command) }
        watch.onWatchEnded = { [weak self] in self?.watchEndedWalk() }
        #endif
    }

    /// After a walk is finished or discarded the belt keeps winding down for a few
    /// seconds; those readings must not start a new walk.
    private var ignoringUntilBeltStops = false
    private var lastSampleSpeed: Double = 0

    private func handle(_ sample: TreadmillSample) {
        defer { lastSampleSpeed = sample.speedKmh }
        if ignoringUntilBeltStops {
            // Stopped, or sped up again (someone restarted it from the remote).
            if sample.speedKmh == 0 { ignoringUntilBeltStops = false }
            guard sample.speedKmh > lastSampleSpeed + 0.05 else { return }
            ignoringUntilBeltStops = false
        }
        if !isSessionActive {
            guard sample.speedKmh > 0 else { return }
            tracker = WorkoutTracker(bodyMassKg: bodyMassKg)
            isSessionActive = true
            saveMessage = nil
            #if os(iOS)
            watch.startWatchWorkout()
            #endif
        }
        tracker.record(sample)
        #if os(iOS)
        watch.send(.padUpdate(speedKmh: sample.speedKmh, distanceMeters: tracker.distanceMeters,
                              isBeltRunning: sample.speedKmh > 0))
        let heartRate = watch.heartRate.map { Int($0.rounded()) } ?? sample.heartRate
        liveActivity.start(tracker, speedKmh: sample.speedKmh, heartRate: heartRate)
        liveActivity.update(tracker, speedKmh: sample.speedKmh, heartRate: heartRate)
        #endif

        if sample.speedKmh == 0, let last = tracker.lastMovingDate,
           sample.date.timeIntervalSince(last) > Self.autoFinishAfter {
            finishSession()
        }
    }

    func finishSession() {
        guard isSessionActive else { return }
        endSession()
        let finished = tracker
        let longEnough = finished.distanceMeters >= 10
        #if os(iOS)
        liveActivity.end(finished, keepSummary: longEnough)
        if watch.isMirroring {
            // The Watch saves the workout, with its heart rate and the pad's distance.
            watch.send(longEnough ? .finish : .discard)
            saveMessage = longEnough
                ? "Saved \(Format.distance(finished.distanceMeters)) to Apple Health from your Apple Watch."
                : "Walk was too short to save."
            return
        }
        #endif
        guard longEnough else {
            saveMessage = "Walk was too short to save."
            return
        }
        #if os(iOS)
        Task { @MainActor in
            do {
                try await health.save(finished)
                saveMessage = "Saved \(Format.distance(finished.distanceMeters)) to Apple Health."
            } catch {
                saveMessage = "Couldn't save to Apple Health: \(error.localizedDescription)"
            }
        }
        #else
        saveMessage = "Walk finished: \(Format.distance(finished.distanceMeters)). Health saving is on the iPhone app."
        #endif
    }

    func discardSession() {
        guard isSessionActive else { return }
        #if os(iOS)
        watch.send(.discard)
        liveActivity.end(tracker, keepSummary: false)
        #endif
        endSession()
        tracker = WorkoutTracker(bodyMassKg: bodyMassKg)
    }

    private func endSession() {
        if pad.isBeltRunning { pad.stop() }
        isSessionActive = false
        ignoringUntilBeltStops = pad.isBeltRunning || lastSampleSpeed > 0
    }

    func toggleBelt() {
        if pad.isBeltRunning {
            pad.stop()
        } else {
            ignoringUntilBeltStops = false
            pad.start()
        }
    }

    #if os(iOS)
    private func handle(_ command: WatchMessage.Command) {
        switch command {
        case .speedUp: pad.adjustSpeed(by: speedStepKmh)
        case .speedDown: pad.adjustSpeed(by: -speedStepKmh)
        case .toggleBelt: toggleBelt()
        case .finish: finishSession()
        }
    }

    /// The walk was ended (and saved or discarded) on the Watch.
    private func watchEndedWalk() {
        guard isSessionActive else { return }
        endSession()
        liveActivity.end(tracker, keepSummary: true)
        saveMessage = "Walk ended on your Apple Watch."
    }
    #endif

    func requestHealthAccess() {
        #if os(iOS)
        Task { try? await health.requestAuthorization() }
        #endif
    }
}

enum Format {
    static func distance(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func speed(_ kmh: Double) -> String {
        String(format: "%.1f", kmh)
    }
}
