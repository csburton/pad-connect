import Foundation

/// What the iPhone and the Watch tell each other during a mirrored workout.
///
/// The iPhone owns the pad connection and streams belt data to the Watch; the
/// Watch owns the workout (heart rate, calories, the saved Health workout) and
/// sends back its stats and any button presses.
public enum WatchMessage: Codable, Equatable {
    // iPhone → Watch
    case padUpdate(speedKmh: Double, distanceMeters: Double, isBeltRunning: Bool)
    /// End the workout and save it to Health.
    case finish
    /// End the workout without saving.
    case discard

    // Watch → iPhone
    case watchStats(heartRate: Double?, activeKcal: Double)
    case command(Command)

    public enum Command: String, Codable {
        case speedUp
        case speedDown
        case toggleBelt
        case finish
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public init?(data: Data) {
        guard let message = try? JSONDecoder().decode(WatchMessage.self, from: data) else { return nil }
        self = message
    }
}
