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
    #endif

    init() {
        let defaults = UserDefaults.standard
        let mass = defaults.object(forKey: "bodyMassKg") as? Double ?? 75
        bodyMassKg = mass
        speedStepKmh = defaults.object(forKey: "speedStepKmh") as? Double ?? 0.5
        tracker = WorkoutTracker(bodyMassKg: mass)
        pad.onSample = { [weak self] sample in self?.handle(sample) }
    }

    private func handle(_ sample: TreadmillSample) {
        if !isSessionActive {
            guard sample.speedKmh > 0 else { return }
            tracker = WorkoutTracker(bodyMassKg: bodyMassKg)
            isSessionActive = true
            saveMessage = nil
        }
        tracker.record(sample)

        if sample.speedKmh == 0, let last = tracker.lastMovingDate,
           sample.date.timeIntervalSince(last) > Self.autoFinishAfter {
            finishSession()
        }
    }

    func finishSession() {
        guard isSessionActive else { return }
        if pad.isBeltRunning { pad.stop() }
        isSessionActive = false
        let finished = tracker
        guard finished.distanceMeters >= 10 else {
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
        isSessionActive = false
        tracker = WorkoutTracker(bodyMassKg: bodyMassKg)
    }

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
