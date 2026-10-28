import ActivityKit
import Foundation

/// The walk shown on the Lock Screen and in the Dynamic Island. Compiled into
/// both the iPhone app (which starts and updates it) and the widget extension
/// (which draws it), so the two always agree on the shape.
struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Time spent walking so far, excluding stops.
        var movingSeconds: TimeInterval
        /// While the belt runs, when the clock would have started had there been
        /// no stops, so the widget can tick the time on its own between updates.
        var clockStart: Date?
        var speedKmh: Double
        var distanceMeters: Double
        var heartRate: Int?
        var isFinished = false

        var isBeltRunning: Bool { clockStart != nil }

        var distanceText: String { String(format: "%.2f", distanceMeters / 1000) }
        var speedText: String { String(format: "%.1f", speedKmh) }

        var durationText: String {
            let total = Int(movingSeconds)
            let h = total / 3600, m = (total % 3600) / 60, s = total % 60
            return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        }
    }
}
