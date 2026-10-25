import HealthKit
import SwiftUI
import WatchKit

@main
struct PadConnectWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var workout = WorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(workout)
                .task { workout.requestAuthorization() }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Called when the iPhone app starts a walk with `startWatchApp`.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WorkoutManager.shared.start(with: workoutConfiguration)
    }
}
