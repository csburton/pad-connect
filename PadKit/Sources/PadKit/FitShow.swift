import Foundation

/// FitShow (运动秀, "Sports Show") vendor protocol, used by the pad's own app.
///
/// Every packet is `0x02, payload..., xor(payload), 0x03`. The app polls status
/// (`0x51`) a couple of times a second and sends control commands (`0x53`).
/// Field layout follows the reverse engineering in qdomyos-zwift's
/// `fitshowtreadmill` driver. Treat anything marked "unverified" with suspicion
/// until it has been checked on the X386P.
public enum FitShow {
    public static let serviceUUID = "FFF0"
    /// Some modules use these alternate services with the same framing.
    public static let alternateServiceUUIDs = ["FFE0", "AE00"]

    static let header: UInt8 = 0x02
    static let footer: UInt8 = 0x03

    public static func frame(_ payload: [UInt8]) -> Data {
        let checksum = payload.reduce(0, ^)
        return Data([header] + payload + [checksum, footer])
    }

    /// Validates framing and checksum and returns the payload.
    public static func unframe(_ data: Data) -> [UInt8]? {
        let bytes = Array(data)
        guard bytes.count >= 4, bytes.first == header, bytes.last == footer else { return nil }
        let payload = Array(bytes[1..<(bytes.count - 2)])
        guard payload.reduce(0, ^) == bytes[bytes.count - 2] else { return nil }
        return payload
    }

    // MARK: Commands

    public enum Command: Equatable {
        case statusPoll
        case requestSpeedInfo
        case requestInclineInfo
        case start
        case stop
        case pause
        /// Incline is in whole machine steps; the X386P has no motorised incline so it stays 0.
        case setSpeed(kmh: Double, incline: Int)

        public var payload: [UInt8] {
            switch self {
            case .statusPoll: return [0x51]
            case .requestSpeedInfo: return [0x50, 0x02]
            case .requestInclineInfo: return [0x50, 0x03]
            // user/sport id 0 (4 bytes), normal mode, no blocks, no mode value
            case .start: return [0x53, 0x01, 0, 0, 0, 0, 0, 0, 0, 0]
            case .stop: return [0x53, 0x03]
            case .pause: return [0x53, 0x06] // unverified
            case .setSpeed(let kmh, let incline):
                return [0x53, 0x02, UInt8(clamping: Int((kmh * 10).rounded())), UInt8(clamping: incline)]
            }
        }

        public var data: Data { FitShow.frame(payload) }
    }

    // MARK: Messages

    public enum Status: UInt8 {
        case normal = 0
        case end = 1
        case starting = 2
        case running = 3
        case stopping = 4
        case error = 5
        case safetyKey = 6
        case study = 7
        case paused = 10
    }

    public struct StatusReport: Equatable {
        public var rawStatus: UInt8
        public var status: Status? { Status(rawValue: rawStatus) }
        public var speedKmh: Double = 0
        public var incline: Int = 0
        public var elapsedSeconds: Int?
        /// Raw distance counter; the unit is unverified, so the app integrates speed instead.
        public var rawDistance: Int?
        public var kcal: Int?
        public var steps: Int?
        public var heartRate: Int?
        /// Seconds left in the start countdown, when status is `.starting`.
        public var countdown: Int?
    }

    public enum Message: Equatable {
        case status(StatusReport)
        case speedInfo(minimumKmh: Double, maximumKmh: Double)
        case ack(command: UInt8, parameter: UInt8)
        case unknown([UInt8])
    }

    public static func parse(_ data: Data) -> Message? {
        guard let p = unframe(data), p.count >= 2 else { return nil }
        func u16(_ i: Int) -> Int { Int(p[i]) | Int(p[i + 1]) << 8 }

        switch p[0] {
        case 0x51:
            var report = StatusReport(rawStatus: p[1])
            switch report.status {
            case .starting:
                if p.count > 2 { report.countdown = Int(p[2]) }
            case .running, .stopping, .paused, .end:
                guard p.count >= 13 else { break }
                report.speedKmh = Double(p[2]) / 10
                report.incline = Int(Int8(bitPattern: p[3]))
                report.elapsedSeconds = u16(4)
                report.rawDistance = u16(6)
                report.kcal = u16(8)
                report.steps = u16(10)
                report.heartRate = p[12] > 0 ? Int(p[12]) : nil
            default:
                break
            }
            return .status(report)
        case 0x50 where p[1] == 0x02 && p.count >= 4:
            return .speedInfo(minimumKmh: Double(p[3]) / 10, maximumKmh: Double(p[2]) / 10)
        case 0x53:
            return .ack(command: p[0], parameter: p[1])
        default:
            return .unknown(p)
        }
    }
}
