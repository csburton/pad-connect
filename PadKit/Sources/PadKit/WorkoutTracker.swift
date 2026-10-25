import Foundation

/// A reading from the pad, whichever protocol it came from.
public struct TreadmillSample: Equatable {
    public var date: Date
    public var speedKmh: Double
    public var inclinePercent: Double
    /// Cumulative step counter from the pad, if it reports one.
    public var machineSteps: Int?
    public var heartRate: Int?

    public init(date: Date, speedKmh: Double, inclinePercent: Double = 0, machineSteps: Int? = nil, heartRate: Int? = nil) {
        self.date = date
        self.speedKmh = speedKmh
        self.inclinePercent = inclinePercent
        self.machineSteps = machineSteps
        self.heartRate = heartRate
    }
}

/// Accumulates one walk from a stream of samples.
///
/// Distance is integrated from belt speed rather than trusted from the pad, and
/// active energy uses the ACSM walking equation (net of resting), so both work
/// the same over FTMS and FitShow.
public struct WorkoutTracker: Equatable {
    /// One minute of the walk, used to write per-minute samples to Apple Health.
    public struct Bucket: Equatable {
        public var start: Date
        public var end: Date
        public var meters: Double
        public var kcal: Double
    }

    public var bodyMassKg: Double
    public private(set) var startDate: Date?
    public private(set) var lastMovingDate: Date?
    public private(set) var distanceMeters: Double = 0
    public private(set) var activeKcal: Double = 0
    public private(set) var movingSeconds: TimeInterval = 0
    public private(set) var buckets: [Bucket] = []
    public private(set) var heartRates: [(date: Date, bpm: Int)] = []

    private var stepsBaseline: Int?
    private var latestMachineSteps: Int?
    private var lastSample: TreadmillSample?

    /// Gaps longer than this (e.g. a dropped connection) aren't counted as walking.
    static let maxInterval: TimeInterval = 5

    public init(bodyMassKg: Double) {
        self.bodyMassKg = bodyMassKg
    }

    public var hasStarted: Bool { startDate != nil }

    public var steps: Int? {
        guard let base = stepsBaseline, let latest = latestMachineSteps, latest >= base else { return nil }
        return latest - base
    }

    public var averageSpeedKmh: Double {
        movingSeconds > 0 ? distanceMeters / movingSeconds * 3.6 : 0
    }

    public mutating func record(_ sample: TreadmillSample) {
        defer { lastSample = sample }

        if startDate == nil {
            guard sample.speedKmh > 0 else { return }
            startDate = sample.date
        }

        if let steps = sample.machineSteps {
            if stepsBaseline == nil { stepsBaseline = steps }
            latestMachineSteps = steps
        }
        if let bpm = sample.heartRate {
            heartRates.append((sample.date, bpm))
        }

        guard let last = lastSample, last.speedKmh > 0 else { return }
        let dt = sample.date.timeIntervalSince(last.date)
        guard dt > 0, dt <= Self.maxInterval else { return }

        let meters = last.speedKmh / 3.6 * dt
        let kcal = Self.activeKcal(speedKmh: last.speedKmh, gradePercent: last.inclinePercent,
                                   bodyMassKg: bodyMassKg, seconds: dt)
        distanceMeters += meters
        activeKcal += kcal
        movingSeconds += dt
        lastMovingDate = sample.date
        addToBucket(at: sample.date, meters: meters, kcal: kcal)
    }

    /// ACSM walking equation without the resting 3.5 ml/kg/min term, at 5 kcal per litre O2.
    static func activeKcal(speedKmh: Double, gradePercent: Double, bodyMassKg: Double, seconds: TimeInterval) -> Double {
        let metersPerMinute = speedKmh * 1000 / 60
        let vo2 = 0.1 * metersPerMinute + 1.8 * metersPerMinute * max(gradePercent, 0) / 100
        return vo2 * bodyMassKg / 1000 * 5 * seconds / 60
    }

    private mutating func addToBucket(at date: Date, meters: Double, kcal: Double) {
        guard let start = startDate else { return }
        let index = Int(date.timeIntervalSince(start) / 60)
        let bucketStart = start.addingTimeInterval(Double(index) * 60)
        if let lastIndex = buckets.indices.last, buckets[lastIndex].start == bucketStart {
            buckets[lastIndex].end = date
            buckets[lastIndex].meters += meters
            buckets[lastIndex].kcal += kcal
        } else {
            buckets.append(Bucket(start: bucketStart, end: date, meters: meters, kcal: kcal))
        }
    }

    public static func == (lhs: WorkoutTracker, rhs: WorkoutTracker) -> Bool {
        lhs.startDate == rhs.startDate && lhs.lastMovingDate == rhs.lastMovingDate &&
            lhs.distanceMeters == rhs.distanceMeters && lhs.buckets == rhs.buckets && lhs.steps == rhs.steps
    }
}
