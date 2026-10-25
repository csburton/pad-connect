import Foundation

/// Bluetooth SIG Fitness Machine Service (FTMS), treadmill subset.
///
/// Spec: https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/
public enum FTMS {
    public static let serviceUUID = "1826"
    public static let featureUUID = "2ACC"
    public static let treadmillDataUUID = "2ACD"
    public static let trainingStatusUUID = "2AD3"
    public static let supportedSpeedRangeUUID = "2AD4"
    public static let controlPointUUID = "2AD9"
    public static let machineStatusUUID = "2ADA"

    // MARK: Treadmill Data (0x2ACD)

    /// One Treadmill Data notification. Fields the pad didn't include are nil.
    public struct TreadmillData: Equatable {
        public var speedKmh: Double?
        public var averageSpeedKmh: Double?
        public var totalDistanceMeters: Double?
        public var inclinePercent: Double?
        public var totalEnergyKcal: Double?
        public var heartRate: Int?
        public var elapsedSeconds: Int?
        public var remainingSeconds: Int?

        public init() {}
    }

    /// Parses a Treadmill Data value. Returns whatever fields could be read if the
    /// packet is shorter than its flags claim, and nil only if the flags are missing.
    public static func parseTreadmillData(_ data: Data) -> TreadmillData? {
        var reader = ByteReader(data)
        guard let flags = reader.u16() else { return nil }
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }

        var result = TreadmillData()

        // Bit 0 is "More Data": instantaneous speed is present when it is CLEAR.
        if !has(0) {
            guard let v = reader.u16() else { return result }
            result.speedKmh = Double(v) / 100
        }
        if has(1) {
            guard let v = reader.u16() else { return result }
            result.averageSpeedKmh = Double(v) / 100
        }
        if has(2) {
            guard let v = reader.u24() else { return result }
            result.totalDistanceMeters = Double(v)
        }
        if has(3) {
            guard let incline = reader.s16(), reader.skip(2) else { return result } // + ramp angle
            result.inclinePercent = Double(incline) / 10
        }
        if has(4) {
            guard reader.skip(4) else { return result } // positive + negative elevation gain
        }
        if has(5) {
            guard reader.skip(1) else { return result } // instantaneous pace
        }
        if has(6) {
            guard reader.skip(1) else { return result } // average pace
        }
        if has(7) {
            guard let total = reader.u16(), reader.skip(3) else { return result } // + per hour, per minute
            if total != 0xFFFF { result.totalEnergyKcal = Double(total) }
        }
        if has(8) {
            guard let hr = reader.u8() else { return result }
            if hr > 0 { result.heartRate = Int(hr) }
        }
        if has(9) {
            guard reader.skip(1) else { return result } // metabolic equivalent
        }
        if has(10) {
            guard let v = reader.u16() else { return result }
            result.elapsedSeconds = Int(v)
        }
        if has(11) {
            guard let v = reader.u16() else { return result }
            result.remainingSeconds = Int(v)
        }
        return result
    }

    // MARK: Supported Speed Range (0x2AD4)

    public struct SpeedRange: Equatable {
        public var minimumKmh: Double
        public var maximumKmh: Double
        public var incrementKmh: Double
    }

    public static func parseSpeedRange(_ data: Data) -> SpeedRange? {
        var reader = ByteReader(data)
        guard let min = reader.u16(), let max = reader.u16(), let inc = reader.u16(), max > min else { return nil }
        return SpeedRange(minimumKmh: Double(min) / 100, maximumKmh: Double(max) / 100, incrementKmh: Double(inc) / 100)
    }

    // MARK: Control Point (0x2AD9)

    public enum ControlCommand: Equatable {
        case requestControl
        case reset
        case setTargetSpeed(kmh: Double)
        case setTargetIncline(percent: Double)
        case startOrResume
        case stop
        case pause

        public var opCode: UInt8 {
            switch self {
            case .requestControl: return 0x00
            case .reset: return 0x01
            case .setTargetSpeed: return 0x02
            case .setTargetIncline: return 0x03
            case .startOrResume: return 0x07
            case .stop, .pause: return 0x08
            }
        }

        public var bytes: Data {
            switch self {
            case .requestControl, .reset, .startOrResume:
                return Data([opCode])
            case .setTargetSpeed(let kmh):
                let value = UInt16(clamping: Int((kmh * 100).rounded()))
                return Data([opCode] + value.littleEndianBytes)
            case .setTargetIncline(let percent):
                let value = UInt16(bitPattern: Int16(clamping: Int((percent * 10).rounded())))
                return Data([opCode] + value.littleEndianBytes)
            case .stop:
                return Data([opCode, 0x01])
            case .pause:
                return Data([opCode, 0x02])
            }
        }
    }

    public enum ResultCode: UInt8 {
        case success = 0x01
        case notSupported = 0x02
        case invalidParameter = 0x03
        case operationFailed = 0x04
        case controlNotPermitted = 0x05
    }

    public struct ControlResponse: Equatable {
        public var requestOpCode: UInt8
        public var result: ResultCode?
        public var rawResult: UInt8

        public var succeeded: Bool { result == .success }
    }

    public static func parseControlResponse(_ data: Data) -> ControlResponse? {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes[0] == 0x80 else { return nil }
        return ControlResponse(requestOpCode: bytes[1], result: ResultCode(rawValue: bytes[2]), rawResult: bytes[2])
    }

    // MARK: Fitness Machine Status (0x2ADA)

    public enum MachineStatus: Equatable {
        case reset
        case stoppedByUser
        case pausedByUser
        case stoppedBySafetyKey
        case startedByUser
        case targetSpeedChanged(kmh: Double)
        case other(UInt8)
    }

    public static func parseMachineStatus(_ data: Data) -> MachineStatus? {
        var reader = ByteReader(data)
        guard let op = reader.u8() else { return nil }
        switch op {
        case 0x01: return .reset
        case 0x02: return reader.u8() == 0x02 ? .pausedByUser : .stoppedByUser
        case 0x03: return .stoppedBySafetyKey
        case 0x04: return .startedByUser
        case 0x05:
            guard let v = reader.u16() else { return .other(op) }
            return .targetSpeedChanged(kmh: Double(v) / 100)
        default: return .other(op)
        }
    }
}
