import HealthKit
import PadKit

/// Writes finished walks to Apple Health as indoor walking workouts.
final class HealthWriter {
    private let store = HKHealthStore()

    private var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
        ]
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // The Watch app shares this app's Health permissions, and reads heart rate
        // during the walk, so ask for read access here too or it never gets asked.
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func save(_ walk: WorkoutTracker) async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let start = walk.startDate, let end = walk.lastMovingDate, end > start else { return }
        try await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .walking
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []
        for bucket in walk.buckets where bucket.end > bucket.start {
            if bucket.meters > 0 {
                samples.append(HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning),
                                                quantity: HKQuantity(unit: .meter(), doubleValue: bucket.meters),
                                                start: bucket.start, end: bucket.end))
            }
            if bucket.kcal > 0 {
                samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: bucket.kcal),
                                                start: bucket.start, end: bucket.end))
            }
        }
        if let steps = walk.steps, steps > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.stepCount),
                                            quantity: HKQuantity(unit: .count(), doubleValue: Double(steps)),
                                            start: start, end: end))
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for reading in walk.heartRates where reading.date >= start && reading.date <= end {
            samples.append(HKQuantitySample(type: HKQuantityType(.heartRate),
                                            quantity: HKQuantity(unit: bpm, doubleValue: Double(reading.bpm)),
                                            start: reading.date, end: reading.date))
        }

        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }
        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}
