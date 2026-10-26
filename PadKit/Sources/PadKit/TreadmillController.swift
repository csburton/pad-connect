#if canImport(CoreBluetooth) && !os(watchOS)
import Combine
import CoreBluetooth
import Foundation

/// Finds, connects to and drives the walking pad over CoreBluetooth.
///
/// Prefers the standard FTMS service and falls back to FitShow's vendor
/// protocol when FTMS isn't there (or when `preferFitShow` is set). All
/// CoreBluetooth callbacks arrive on the main queue, so published state is
/// only ever touched from the main thread.
public final class TreadmillController: NSObject, ObservableObject {
    public enum ConnectionState: Equatable {
        case bluetoothOff
        case unauthorized
        case idle
        case scanning
        case connecting(name: String)
        case connected(name: String)
    }

    public enum ProtocolKind: String {
        case ftms = "FTMS"
        case fitShow = "FitShow"
        case simulated = "Simulated"
    }

    public struct DiscoveredPad: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public var rssi: Int
    }

    @Published public private(set) var state: ConnectionState = .idle
    @Published public private(set) var discovered: [DiscoveredPad] = []
    @Published public private(set) var protocolKind: ProtocolKind?
    @Published public private(set) var speedKmh: Double = 0
    @Published public private(set) var inclinePercent: Double = 0
    @Published public private(set) var heartRate: Int?
    @Published public private(set) var machineSteps: Int?
    @Published public private(set) var isBeltRunning = false
    @Published public private(set) var minimumSpeedKmh: Double = 1.0
    @Published public private(set) var maximumSpeedKmh: Double = 6.0
    @Published public private(set) var speedIncrementKmh: Double = 0.1
    @Published public private(set) var lastError: String?
    /// The pad has gone to sleep and ignores commands until a button on its remote is pressed.
    @Published public private(set) var isInStandby = false

    /// Called for every reading from the pad, about once a second or faster.
    public var onSample: ((TreadmillSample) -> Void)?

    public var preferFitShow: Bool {
        get { UserDefaults.standard.bool(forKey: Self.preferFitShowKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.preferFitShowKey) }
    }

    public var rememberedPadID: UUID? {
        UserDefaults.standard.string(forKey: Self.lastPadKey).flatMap(UUID.init(uuidString:))
    }

    private static let lastPadKey = "lastPadIdentifier"
    private static let preferFitShowKey = "preferFitShow"

    private static let ftmsService = CBUUID(string: FTMS.serviceUUID)
    private static let fitShowServices = ([FitShow.serviceUUID] + FitShow.alternateServiceUUIDs).map { CBUUID(string: $0) }

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var pad: CBPeripheral?
    private var userDisconnected = false
    private var servicesAwaitingCharacteristics = 0

    // FTMS
    private var ftmsTreadmillData: CBCharacteristic?
    private var ftmsControlPoint: CBCharacteristic?
    private var ftmsMachineStatus: CBCharacteristic?
    private var ftmsSpeedRange: CBCharacteristic?
    private var ftmsQueue: [FTMS.ControlCommand] = []
    private var ftmsInFlight: FTMS.ControlCommand?
    private var ftmsTimeout: Timer?
    private var hasControl = false

    // FitShow
    private var fitShowNotify: CBCharacteristic?
    private var fitShowWrite: CBCharacteristic?
    private var pollTimer: Timer?

    /// Speed to apply once the belt has actually started moving.
    private var pendingSpeedKmh: Double?

    // Simulated pad (iOS Simulator only, which has no Bluetooth)
    public static let simulatedPadID = UUID(uuidString: "5E1A7ED0-0000-4000-8000-000000000001")!
    private var simTimer: Timer?
    private var simTargetKmh: Double = 0
    private var simSteps: Double = 0

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        #if targetEnvironment(simulator)
        discovered = [DiscoveredPad(id: Self.simulatedPadID, name: "Simulated pad", rssi: -40)]
        #endif
    }

    // MARK: Scanning and connecting

    public func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        if pad == nil { state = .scanning }
        // Scan for everything: some pads don't advertise their services.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    public func connect(_ id: UUID) {
        if id == Self.simulatedPadID {
            connectSimulated()
            return
        }
        guard let peripheral = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        central.stopScan()
        userDisconnected = false
        pad = peripheral
        state = .connecting(name: peripheral.name ?? "Walking pad")
        central.connect(peripheral)
    }

    public func disconnect(forget: Bool = false) {
        userDisconnected = true
        if forget { UserDefaults.standard.removeObject(forKey: Self.lastPadKey) }
        if let pad { central.cancelPeripheralConnection(pad) }
        pad = nil
        resetConnection()
        state = .idle
        #if targetEnvironment(simulator)
        discovered = [DiscoveredPad(id: Self.simulatedPadID, name: "Simulated pad", rssi: -40)]
        #endif
    }

    // MARK: Control

    public func start(atKmh speed: Double? = nil) {
        lastError = nil
        let target = speed.map(clampSpeed)
        switch protocolKind {
        case .ftms:
            pendingSpeedKmh = target
            sendFTMS(.startOrResume)
        case .fitShow:
            pendingSpeedKmh = target
            if isInStandby {
                // Unverified: there's no documented wake command, so try resetting the
                // pad with a stop before starting, as a remote button press seems to.
                writeFitShow(.stop)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.writeFitShow(.start)
                }
            } else {
                writeFitShow(.start)
            }
        case .simulated:
            simTargetKmh = target ?? minimumSpeedKmh
        case nil:
            break
        }
    }

    public func stop() {
        pendingSpeedKmh = nil
        switch protocolKind {
        case .ftms: sendFTMS(.stop)
        case .fitShow: writeFitShow(.stop)
        case .simulated: simTargetKmh = 0
        case nil: break
        }
    }

    public func pause() {
        pendingSpeedKmh = nil
        switch protocolKind {
        case .ftms: sendFTMS(.pause)
        case .fitShow: writeFitShow(.pause)
        case .simulated: simTargetKmh = 0
        case nil: break
        }
    }

    public func setSpeed(_ kmh: Double) {
        let target = clampSpeed(kmh)
        guard isBeltRunning else {
            start(atKmh: target)
            return
        }
        switch protocolKind {
        case .ftms: sendFTMS(.setTargetSpeed(kmh: target))
        case .fitShow: writeFitShow(.setSpeed(kmh: target, incline: 0))
        case .simulated: simTargetKmh = target
        case nil: break
        }
    }

    public func adjustSpeed(by delta: Double) {
        guard isBeltRunning else { return }
        let current = protocolKind == .simulated ? simTargetKmh : (pendingSpeedKmh ?? speedKmh)
        setSpeed(current + delta)
    }

    private func clampSpeed(_ kmh: Double) -> Double {
        let stepped = (kmh / speedIncrementKmh).rounded() * speedIncrementKmh
        return min(max(stepped, minimumSpeedKmh), maximumSpeedKmh)
    }

    // MARK: FTMS

    private func sendFTMS(_ command: FTMS.ControlCommand) {
        if !hasControl && command != .requestControl && !ftmsQueue.contains(.requestControl) && ftmsInFlight != .requestControl {
            ftmsQueue.append(.requestControl)
        }
        ftmsQueue.append(command)
        sendNextFTMS()
    }

    private func sendNextFTMS() {
        guard ftmsInFlight == nil, !ftmsQueue.isEmpty, let pad, let cp = ftmsControlPoint else { return }
        let command = ftmsQueue.removeFirst()
        ftmsInFlight = command
        pad.writeValue(command.bytes, for: cp, type: .withResponse)
        ftmsTimeout?.invalidate()
        ftmsTimeout = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.finishFTMSCommand()
        }
    }

    private func finishFTMSCommand() {
        ftmsTimeout?.invalidate()
        ftmsInFlight = nil
        sendNextFTMS()
    }

    private func handleFTMSResponse(_ response: FTMS.ControlResponse) {
        guard let command = ftmsInFlight, command.opCode == response.requestOpCode else { return }
        if command == .requestControl {
            // Some pads refuse or ignore Request Control but accept commands anyway.
            hasControl = true
        } else if !response.succeeded {
            lastError = "The pad rejected \(command) (\(response.result.map { "\($0)" } ?? "code \(response.rawResult)"))."
        } else if command == .startOrResume, let target = pendingSpeedKmh {
            pendingSpeedKmh = nil
            ftmsQueue.insert(.setTargetSpeed(kmh: target), at: 0)
        }
        finishFTMSCommand()
    }

    private func handleTreadmillData(_ data: FTMS.TreadmillData) {
        guard let speed = data.speedKmh else { return } // continuation packet
        speedKmh = speed
        if let incline = data.inclinePercent { inclinePercent = incline }
        heartRate = data.heartRate
        isBeltRunning = speed > 0
        if isBeltRunning, let target = pendingSpeedKmh {
            pendingSpeedKmh = nil
            sendFTMS(.setTargetSpeed(kmh: target))
        }
        emitSample()
    }

    private func handleMachineStatus(_ status: FTMS.MachineStatus) {
        switch status {
        case .stoppedByUser, .pausedByUser, .stoppedBySafetyKey:
            isBeltRunning = false
            speedKmh = 0
            emitSample()
        default:
            break
        }
    }

    // MARK: FitShow

    private func writeFitShow(_ command: FitShow.Command) {
        guard let pad, let characteristic = fitShowWrite else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        pad.writeValue(command.data, for: characteristic, type: type)
    }

    private func handleFitShow(_ message: FitShow.Message) {
        switch message {
        case .status(let report):
            let running = report.status == .running
            isBeltRunning = running
            speedKmh = running ? report.speedKmh : 0
            inclinePercent = Double(report.incline)
            if let steps = report.steps { machineSteps = steps }
            heartRate = report.heartRate
            isInStandby = report.status == .standby
            if running, let target = pendingSpeedKmh {
                pendingSpeedKmh = nil
                writeFitShow(.setSpeed(kmh: target, incline: 0))
            }
            emitSample()
        case .speedInfo(let minimum, let maximum):
            if maximum > minimum {
                minimumSpeedKmh = minimum
                maximumSpeedKmh = maximum
            }
        case .ack, .unknown:
            break
        }
    }

    // MARK: Shared

    private func emitSample() {
        onSample?(TreadmillSample(date: Date(), speedKmh: speedKmh, inclinePercent: inclinePercent,
                                  machineSteps: machineSteps, heartRate: heartRate))
    }

    private func chooseProtocol() {
        guard let pad, protocolKind == nil else { return }
        let ftmsReady = ftmsTreadmillData != nil && ftmsControlPoint != nil
        let fitShowReady = fitShowNotify != nil && fitShowWrite != nil

        if ftmsReady && (!preferFitShow || !fitShowReady) {
            protocolKind = .ftms
            for characteristic in [ftmsTreadmillData, ftmsControlPoint, ftmsMachineStatus].compactMap({ $0 }) {
                pad.setNotifyValue(true, for: characteristic)
            }
            if let ftmsSpeedRange { pad.readValue(for: ftmsSpeedRange) }
            sendFTMS(.requestControl)
        } else if fitShowReady, let notify = fitShowNotify {
            protocolKind = .fitShow
            pad.setNotifyValue(true, for: notify)
            writeFitShow(.requestSpeedInfo)
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.writeFitShow(.statusPoll)
            }
        } else {
            lastError = "This device doesn't look like a supported walking pad."
            disconnect()
            return
        }
        state = .connected(name: pad.name ?? "Walking pad")
        UserDefaults.standard.set(pad.identifier.uuidString, forKey: Self.lastPadKey)
    }

    private func resetConnection() {
        simTimer?.invalidate()
        simTimer = nil
        simTargetKmh = 0
        pollTimer?.invalidate()
        pollTimer = nil
        ftmsTimeout?.invalidate()
        ftmsQueue = []
        ftmsInFlight = nil
        hasControl = false
        ftmsTreadmillData = nil
        ftmsControlPoint = nil
        ftmsMachineStatus = nil
        ftmsSpeedRange = nil
        fitShowNotify = nil
        fitShowWrite = nil
        protocolKind = nil
        pendingSpeedKmh = nil
        servicesAwaitingCharacteristics = 0
        isInStandby = false
        if isBeltRunning || speedKmh > 0 {
            isBeltRunning = false
            speedKmh = 0
            emitSample()
        }
    }

    private func reconnectToRememberedPad() {
        guard let id = rememberedPadID, pad == nil,
              let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        pad = peripheral
        userDisconnected = false
        state = .connecting(name: peripheral.name ?? "Walking pad")
        // A pending connect never times out, so this also waits for the pad to be switched on.
        central.connect(peripheral)
    }

    static func looksLikePad(name: String?, advertisement: [String: Any]) -> Bool {
        let services = (advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + Array((advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]).keys)
        if services.contains(ftmsService) || services.contains(where: { fitShowServices.contains($0) }) { return true }
        return name?.uppercased().hasPrefix("FS-") == true
    }
}

// MARK: - Simulated pad

extension TreadmillController {
    /// A pretend pad for the iOS Simulator. It ramps speed up and down like the
    /// real belt (including the wind-down after Stop) and makes up steps and heart rate.
    private func connectSimulated() {
        resetConnection()
        pad = nil
        protocolKind = .simulated
        minimumSpeedKmh = 1.0
        maximumSpeedKmh = 6.0
        speedIncrementKmh = 0.1
        simSteps = 0
        state = .connected(name: "Simulated pad")
        let interval: TimeInterval = 0.5
        simTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tickSimulated(interval)
        }
    }

    private func tickSimulated(_ dt: TimeInterval) {
        // About 0.5 km/h per second each way, like the X386P.
        let maxChange = 0.5 * dt
        let delta = simTargetKmh - speedKmh
        var speed = speedKmh + min(max(delta, -maxChange), maxChange)
        if simTargetKmh == 0 && speed < minimumSpeedKmh * 0.5 { speed = 0 }
        speed = (speed * 100).rounded() / 100

        speedKmh = speed
        isBeltRunning = speed > 0
        if speed > 0 {
            simSteps += speed / 3.6 * dt / 0.7 // ~0.7 m stride
            heartRate = Int(85 + speed * 9 + Double.random(in: -2...2))
        } else {
            heartRate = nil
        }
        machineSteps = Int(simSteps)
        emitSample()
    }
}

// MARK: - CBCentralManagerDelegate

extension TreadmillController: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard protocolKind != .simulated else { return }
        switch central.state {
        case .poweredOn:
            if case .bluetoothOff = state { state = .idle }
            if case .unauthorized = state { state = .idle }
            reconnectToRememberedPad()
            startScan()
        case .unauthorized:
            state = .unauthorized
        default:
            resetConnection()
            pad = nil
            state = .bluetoothOff
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard Self.looksLikePad(name: name, advertisement: advertisementData) else { return }
        peripherals[peripheral.identifier] = peripheral
        if let index = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            discovered[index].rssi = RSSI.intValue
        } else {
            discovered.append(DiscoveredPad(id: peripheral.identifier, name: name ?? "Unknown pad", rssi: RSSI.intValue))
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.ftmsService] + Self.fitShowServices)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastError = error?.localizedDescription ?? "Couldn't connect to the pad."
        resetConnection()
        pad = nil
        state = .idle
        startScan()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetConnection()
        if userDisconnected {
            pad = nil
            return
        }
        // Dropped (pad switched off or out of range): keep trying in the background.
        state = .connecting(name: peripheral.name ?? "Walking pad")
        central.connect(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension TreadmillController: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        servicesAwaitingCharacteristics = services.count
        if services.isEmpty { chooseProtocol() }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        if service.uuid == Self.ftmsService {
            for c in characteristics {
                switch c.uuid {
                case CBUUID(string: FTMS.treadmillDataUUID): ftmsTreadmillData = c
                case CBUUID(string: FTMS.controlPointUUID): ftmsControlPoint = c
                case CBUUID(string: FTMS.machineStatusUUID): ftmsMachineStatus = c
                case CBUUID(string: FTMS.supportedSpeedRangeUUID): ftmsSpeedRange = c
                default: break
                }
            }
        } else if Self.fitShowServices.contains(service.uuid), fitShowWrite == nil {
            fitShowNotify = characteristics.first { $0.properties.contains(.notify) }
            fitShowWrite = characteristics.first {
                $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
            }
        }
        servicesAwaitingCharacteristics -= 1
        if servicesAwaitingCharacteristics <= 0 { chooseProtocol() }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        if characteristic == ftmsTreadmillData {
            if let data = FTMS.parseTreadmillData(value) { handleTreadmillData(data) }
        } else if characteristic == ftmsControlPoint {
            if let response = FTMS.parseControlResponse(value) { handleFTMSResponse(response) }
        } else if characteristic == ftmsMachineStatus {
            if let status = FTMS.parseMachineStatus(value) { handleMachineStatus(status) }
        } else if characteristic == ftmsSpeedRange {
            if let range = FTMS.parseSpeedRange(value) {
                minimumSpeedKmh = range.minimumKmh
                maximumSpeedKmh = range.maximumKmh
                if range.incrementKmh > 0 { speedIncrementKmh = range.incrementKmh }
            }
        } else if characteristic == fitShowNotify {
            if let message = FitShow.parse(value) { handleFitShow(message) }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // A failed write to the control point gets no indication, so don't wait for the timeout.
        if characteristic == ftmsControlPoint, let error {
            lastError = error.localizedDescription
            finishFTMSCommand()
        }
    }
}
#endif
