import XCTest
@testable import PadKit

final class FTMSTests: XCTestCase {
    func testTreadmillDataWithSpeedDistanceEnergyAndTime() {
        // flags: distance (bit 2), energy (bit 7), elapsed time (bit 10)
        let flags: UInt16 = (1 << 2) | (1 << 7) | (1 << 10)
        var bytes = flags.littleEndianBytes
        bytes += UInt16(420).littleEndianBytes // 4.20 km/h
        bytes += [0x2C, 0x01, 0x00] // 300 m
        bytes += UInt16(25).littleEndianBytes + [0xFF, 0xFF, 0xFF] // 25 kcal, per hour/min n/a
        bytes += UInt16(600).littleEndianBytes // 600 s

        let data = FTMS.parseTreadmillData(Data(bytes))
        XCTAssertEqual(data?.speedKmh, 4.2)
        XCTAssertEqual(data?.totalDistanceMeters, 300)
        XCTAssertEqual(data?.totalEnergyKcal, 25)
        XCTAssertEqual(data?.elapsedSeconds, 600)
        XCTAssertNil(data?.inclinePercent)
    }

    func testMoreDataFlagMeansNoSpeed() {
        let data = FTMS.parseTreadmillData(Data([0x01, 0x00]))
        XCTAssertNotNil(data)
        XCTAssertNil(data?.speedKmh)
    }

    func testTruncatedPacketKeepsWhatWasRead() {
        let flags: UInt16 = 1 << 2
        let data = FTMS.parseTreadmillData(Data(flags.littleEndianBytes + UInt16(300).littleEndianBytes))
        XCTAssertEqual(data?.speedKmh, 3)
        XCTAssertNil(data?.totalDistanceMeters)
    }

    func testControlCommandBytes() {
        XCTAssertEqual(FTMS.ControlCommand.requestControl.bytes, Data([0x00]))
        XCTAssertEqual(FTMS.ControlCommand.setTargetSpeed(kmh: 3.5).bytes, Data([0x02, 0x5E, 0x01]))
        XCTAssertEqual(FTMS.ControlCommand.startOrResume.bytes, Data([0x07]))
        XCTAssertEqual(FTMS.ControlCommand.stop.bytes, Data([0x08, 0x01]))
        XCTAssertEqual(FTMS.ControlCommand.pause.bytes, Data([0x08, 0x02]))
        XCTAssertEqual(FTMS.ControlCommand.setTargetIncline(percent: -1.5).bytes, Data([0x03, 0xF1, 0xFF]))
    }

    func testControlResponse() {
        let response = FTMS.parseControlResponse(Data([0x80, 0x02, 0x01]))
        XCTAssertEqual(response?.requestOpCode, 0x02)
        XCTAssertTrue(response?.succeeded ?? false)
        XCTAssertEqual(FTMS.parseControlResponse(Data([0x80, 0x07, 0x05]))?.result, .controlNotPermitted)
    }

    func testSpeedRangeAndStatus() {
        let range = FTMS.parseSpeedRange(Data(UInt16(100).littleEndianBytes + UInt16(600).littleEndianBytes + UInt16(10).littleEndianBytes))
        XCTAssertEqual(range, FTMS.SpeedRange(minimumKmh: 1, maximumKmh: 6, incrementKmh: 0.1))
        XCTAssertEqual(FTMS.parseMachineStatus(Data([0x02, 0x02])), .pausedByUser)
        XCTAssertEqual(FTMS.parseMachineStatus(Data([0x02, 0x01])), .stoppedByUser)
        XCTAssertEqual(FTMS.parseMachineStatus(Data([0x05, 0x90, 0x01])), .targetSpeedChanged(kmh: 4))
    }
}

final class FitShowTests: XCTestCase {
    func testFraming() {
        XCTAssertEqual(FitShow.Command.statusPoll.data, Data([0x02, 0x51, 0x51, 0x03]))
        XCTAssertEqual(FitShow.Command.setSpeed(kmh: 4.0, incline: 0).data, Data([0x02, 0x53, 0x02, 0x28, 0x00, 0x79, 0x03]))
        XCTAssertEqual(FitShow.unframe(Data([0x02, 0x53, 0x03, 0x50, 0x03])), [0x53, 0x03])
        XCTAssertNil(FitShow.unframe(Data([0x02, 0x53, 0x03, 0x51, 0x03])), "bad checksum")
    }

    func testRunningStatus() {
        // status running, 3.5 km/h, incline 0, 125 s, distance 12, 9 kcal, 180 steps, no HR
        let payload: [UInt8] = [0x51, 0x03, 35, 0, 125, 0, 12, 0, 9, 0, 180, 0, 0, 0]
        guard case .status(let report) = FitShow.parse(FitShow.frame(payload)) else {
            return XCTFail("expected status")
        }
        XCTAssertEqual(report.status, .running)
        XCTAssertEqual(report.speedKmh, 3.5)
        XCTAssertEqual(report.elapsedSeconds, 125)
        XCTAssertEqual(report.kcal, 9)
        XCTAssertEqual(report.steps, 180)
        XCTAssertNil(report.heartRate)
    }

    func testIdleStatusAndSpeedInfo() {
        guard case .status(let idle) = FitShow.parse(FitShow.frame([0x51, 0x00])) else {
            return XCTFail("expected status")
        }
        XCTAssertEqual(idle.status, .normal)
        XCTAssertEqual(idle.speedKmh, 0)
        XCTAssertEqual(FitShow.parse(FitShow.frame([0x50, 0x02, 60, 10, 0])), .speedInfo(minimumKmh: 1, maximumKmh: 6))
    }
}

final class WorkoutTrackerTests: XCTestCase {
    func testIntegratesDistanceAndSteps() {
        var tracker = WorkoutTracker(bodyMassKg: 80)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        tracker.record(TreadmillSample(date: t0, speedKmh: 0, machineSteps: 50))
        XCTAssertFalse(tracker.hasStarted)

        // 3.6 km/h = 1 m/s for 120 seconds, one sample per second
        for second in 0...120 {
            tracker.record(TreadmillSample(date: t0.addingTimeInterval(Double(10 + second)), speedKmh: 3.6,
                                           machineSteps: 100 + second * 2))
        }
        XCTAssertEqual(tracker.distanceMeters, 120, accuracy: 0.001)
        XCTAssertEqual(tracker.movingSeconds, 120, accuracy: 0.001)
        XCTAssertEqual(tracker.steps, 240)
        XCTAssertEqual(tracker.buckets.count, 3) // 0-60, 60-120, and the final second
        XCTAssertEqual(tracker.buckets.map(\.meters).reduce(0, +), 120, accuracy: 0.001)
        // 60 m/min, flat, 80 kg: 6 ml/kg/min * 80 / 1000 * 5 = 2.4 kcal/min
        XCTAssertEqual(tracker.activeKcal, 4.8, accuracy: 0.001)
        XCTAssertEqual(tracker.averageSpeedKmh, 3.6, accuracy: 0.001)
    }

    func testIgnoresLongGaps() {
        var tracker = WorkoutTracker(bodyMassKg: 70)
        let t0 = Date()
        tracker.record(TreadmillSample(date: t0, speedKmh: 3.6))
        tracker.record(TreadmillSample(date: t0.addingTimeInterval(60), speedKmh: 3.6))
        XCTAssertEqual(tracker.distanceMeters, 0)
    }
}

final class WatchMessageTests: XCTestCase {
    func testRoundTrip() {
        let messages: [WatchMessage] = [
            .padUpdate(speedKmh: 4.5, distanceMeters: 1234.5, isBeltRunning: true),
            .finish,
            .discard,
            .watchStats(heartRate: 112, activeKcal: 87.5),
            .watchStats(heartRate: nil, activeKcal: 0),
            .command(.speedUp),
        ]
        for message in messages {
            XCTAssertEqual(WatchMessage(data: message.encoded()), message)
        }
        XCTAssertNil(WatchMessage(data: Data("nonsense".utf8)))
    }
}
