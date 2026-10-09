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

/// CoreBluetooth adapter. Commands go through `OlleeSession` (same façade as tests).
final class CoreBluetoothNUS: NUSLink, @unchecked Sendable {
    var onWrite: (([UInt8]) -> Void)?
    let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation

    init() {
        var cont: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream(bufferingPolicy: .bufferingOldest(16)) { cont = $0 }
        continuation = cont
    }

    func connect() async throws {}

    func write(_ chunks: [[UInt8]]) async throws {
        for chunk in chunks {
            onWrite?(chunk)
        }
    }

    func ingest(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }
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
    private var radio: CoreBluetoothNUS?
    private var session: OlleeSession?
    private var worldTimeHeader: [UInt8]

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
        try await commands().setNameTag(text)
    }

    func beep() async throws {
        try await commands().beep()
    }

    func setClockCounter(_ count: Int) async throws {
        let session = try commands()
        try await session.setClockCounter(count)
        worldTimeHeader = session.worldTimeHeader
        UserDefaults.standard.set(Data(worldTimeHeader), forKey: headerKey)
    }

    func showLight(red: UInt8, green: UInt8, blue: UInt8) async throws {
        try await commands().showLight(red: red, green: green, blue: blue)
    }

    private func commands() throws -> OlleeSession {
        guard let session else { throw OlleeError.notReady }
        return session
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

    private func attachSession() {
        let radio = CoreBluetoothNUS()
        radio.onWrite = { [weak self] chunk in
            guard let self, let peripheral = self.peripheral, let rx = self.rx else { return }
            let type: CBCharacteristicWriteType =
                rx.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(Data(chunk), for: rx, type: type)
        }
        self.radio = radio
        let session = OlleeSession(link: radio, worldTimeHeader: worldTimeHeader)
        self.session = session
        Task { @MainActor in
            do {
                try await session.connect()
                self.state = .ready
                self.lastError = nil
            } catch {
                self.fail(error.localizedDescription)
            }
        }
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
            self.radio = nil
            self.session = nil
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
                self.attachSession()
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
            self.radio?.ingest(Array(data))
        }
    }
}
