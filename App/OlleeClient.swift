import Combine
import CoreBluetooth
import Foundation

enum NUS {
    static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rx = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let tx = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
}

enum ConnectionState: Equatable {
    case poweredOff
    case idle
    case scanning
    case connecting
    case ready
}

enum OlleeError: Error, Equatable {
    case notReady
    case timeout
    case lightUnpublished
}

@MainActor
final class OlleeClient: NSObject, ObservableObject {
    static let shared = OlleeClient()

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var deviceName: String?
    @Published var lastError: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var notifyBuffer = Data()
    private var worldTimeHeader: [UInt8]
    private var readWaiter: (UInt8, CheckedContinuation<Frame, Error>)?
    private var readGeneration = 0

    private let savedUUIDKey = "ollee.peripheralUUID"
    private let headerKey = "ollee.worldTimeHeader"

    override init() {
        if let saved = UserDefaults.standard.data(forKey: headerKey), saved.count == ClockCounter.headerSize {
            worldTimeHeader = Array(saved)
        } else {
            worldTimeHeader = [0, 0, 0, 0]
        }
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        lastError = nil
        guard central.state == .poweredOn else {
            noteBluetoothOff()
            return
        }
        state = .scanning
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func setNameTag(_ text: String) async throws {
        try await send(try NameTag.frame(text: text))
    }

    func beep() async throws {
        let reply = try await request(Frame.read(target: Beep.readTarget), expecting: Beep.readTarget &+ 0x20)
        try await send(try Beep.previewFrame(storedReadback: reply.payload))
    }

    func setClockCounter(_ count: Int) async throws {
        let reply = try? await request(
            Frame.read(target: ClockCounter.readTarget),
            expecting: ClockCounter.readTarget &+ 0x20
        )
        if let header = reply?.payload.prefix(ClockCounter.headerSize), header.count == ClockCounter.headerSize {
            worldTimeHeader = Array(header)
            UserDefaults.standard.set(Data(worldTimeHeader), forKey: headerKey)
        }
        try await send(try ClockCounter.frame(count: count, worldTimeHeader: worldTimeHeader))
    }

    func showLight(red: UInt8, green: UInt8, blue: UInt8) async throws {
        do {
            _ = try Light.show(red: red, green: green, blue: blue)
        } catch LightError.registerUnpublished {
            throw OlleeError.lightUnpublished
        }
    }

    private func send(_ frame: Frame) async throws {
        guard state == .ready, let peripheral, let rx else {
            throw OlleeError.notReady
        }
        let type: CBCharacteristicWriteType = rx.properties.contains(.write) ? .withResponse : .withoutResponse
        for chunk in Frame.attChunks(frame.encoded()) {
            peripheral.writeValue(Data(chunk), for: rx, type: type)
        }
    }

    private func request(_ frame: Frame, expecting target: UInt8) async throws -> Frame {
        readGeneration += 1
        let generation = readGeneration
        return try await withCheckedThrowingContinuation { continuation in
            readWaiter = (target, continuation)
            Task { @MainActor in
                do {
                    try await self.send(frame)
                } catch {
                    self.failWaiter(generation: generation, error: error)
                }
            }
            Task { @MainActor in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                self.failWaiter(generation: generation, error: OlleeError.timeout)
            }
        }
    }

    private func failWaiter(generation: Int, error: Error) {
        guard readGeneration == generation, let waiter = readWaiter else { return }
        readWaiter = nil
        waiter.1.resume(throwing: error)
    }

    private func connect(_ peripheral: CBPeripheral) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    private func fail(_ message: String) {
        lastError = message
        if state == .ready { return }
        state = .idle
    }

    private func noteBluetoothOff() {
        state = .poweredOff
        lastError = "Bluetooth is off"
    }
}

extension OlleeClient: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if self.state == .poweredOff { self.state = .idle }
                if let uuid = UserDefaults.standard.string(forKey: self.savedUUIDKey).flatMap(UUID.init),
                   let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
                    self.connect(known)
                }
            case .poweredOff:
                self.noteBluetoothOff()
            case .resetting, .unauthorized, .unknown, .unsupported:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi _: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isOllee = name.localizedCaseInsensitiveContains("ollee") || services.contains(NUS.service)
        guard isOllee else { return }
        Task { @MainActor in self.connect(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: self.savedUUIDKey)
            self.deviceName = peripheral.name ?? "Ollee"
            peripheral.discoverServices([NUS.service])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in self.fail(error?.localizedDescription ?? "Connect failed") }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.rx = nil
            self.tx = nil
            self.state = .idle
            if let error { self.lastError = error.localizedDescription }
        }
    }
}

extension OlleeClient: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error { self.fail(error.localizedDescription); return }
            peripheral.services?.forEach { peripheral.discoverCharacteristics([NUS.rx, NUS.tx], for: $0) }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error { self.fail(error.localizedDescription); return }
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == NUS.rx { self.rx = characteristic }
                if characteristic.uuid == NUS.tx {
                    self.tx = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if self.rx != nil, self.tx != nil {
                self.state = .ready
                self.lastError = nil
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        Task { @MainActor in
            if let error { self.lastError = error.localizedDescription; return }
            self.notifyBuffer.append(data)
            while self.notifyBuffer.count >= 2 {
                let total = 2 + Int(self.notifyBuffer[1])
                guard self.notifyBuffer.count >= total else { return }
                let bytes = Array(self.notifyBuffer.prefix(total))
                self.notifyBuffer.removeFirst(total)
                guard let frame = Frame.parse(bytes) else { continue }
                if let waiter = self.readWaiter, waiter.0 == frame.target {
                    self.readWaiter = nil
                    waiter.1.resume(returning: frame)
                }
            }
        }
    }
}
