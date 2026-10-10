import Combine
import CoreBluetooth
import Foundation

enum NUS {
    static let service = CBUUID(string: OlleeAdvertisement.nordicUARTService)
    static let rx = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let tx = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
}

struct BLECandidate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let match: OlleeAdvertisement
    let isLastUsed: Bool
    let rssi: Int
}

enum ConnectionState: Equatable {
    case poweredOff
    case idle
    case scanning
    case connecting
    case ready
}

/// GATT byte pipe. Created after RX exists; chunks writes; throws once finished.
@MainActor
final class CoreBluetoothNUS: NUSLink {
    private let peripheral: CBPeripheral
    private let rx: CBCharacteristic
    private let continuation: AsyncStream<[UInt8]>.Continuation
    let incoming: AsyncStream<[UInt8]>
    private var alive = true

    init(peripheral: CBPeripheral, rx: CBCharacteristic) {
        self.peripheral = peripheral
        self.rx = rx
        var cont: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream { cont = $0 }
        continuation = cont
    }

    func write(_ bytes: [UInt8]) async throws {
        guard alive else { throw OlleeError.notReady }
        let type: CBCharacteristicWriteType =
            rx.properties.contains(.write) ? .withResponse : .withoutResponse
        for chunk in Frame.attChunks(bytes) {
            peripheral.writeValue(Data(chunk), for: rx, type: type)
        }
    }

    func ingest(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }

    func finish() {
        alive = false
        continuation.finish()
    }
}

@MainActor
final class OlleeClient: NSObject, ObservableObject {
    static let shared = OlleeClient()

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var deviceName: String?
    @Published private(set) var candidates: [BLECandidate] = []
    @Published var lastError: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var radio: CoreBluetoothNUS?
    private var session: OlleeSession?

    private let savedUUIDKey = "ollee.peripheralUUID"
    private let headerKey = "ollee.worldTimeHeader"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        lastError = nil
        guard central.state == .poweredOn else {
            noteBluetoothOff()
            return
        }
        if state == .scanning {
            stopScan()
            return
        }
        beginScan()
    }

    func connect(to id: UUID) {
        guard let peripheral = discovered[id] else { return }
        lastError = nil
        clearCandidates()
        connect(peripheral)
    }

    func setNameTag(_ text: String) async throws {
        try await commands().setNameTag(text)
    }

    func beep() async throws {
        try await commands().beep()
    }

    func setClockCounter(_ count: Int) async throws {
        let session = try commands()
        defer { UserDefaults.standard.set(Data(session.worldTimeHeader), forKey: headerKey) }
        try await session.setClockCounter(count)
    }

    func showLight(red: UInt8, green: UInt8, blue: UInt8) async throws {
        try await commands().showLight(red: red, green: green, blue: blue)
    }

    private func commands() throws -> OlleeSession {
        guard let session else { throw OlleeError.notReady }
        return session
    }

    private func storedWorldTimeHeader() -> [UInt8] {
        if let saved = UserDefaults.standard.data(forKey: headerKey), saved.count == ClockCounter.headerSize {
            return Array(saved)
        }
        return [0, 0, 0, 0]
    }

    private func beginScan() {
        if let peripheral, state == .ready || state == .connecting {
            dropRadio()
            rx = nil
            tx = nil
            deviceName = nil
            central.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
        }
        clearCandidates()
        state = .scanning
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func stopScan() {
        central.stopScan()
        clearCandidates()
        state = .idle
    }

    private func connect(_ peripheral: CBPeripheral) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        central.connect(peripheral, options: nil)
    }

    private func record(
        peripheral: CBPeripheral,
        name: String,
        match: OlleeAdvertisement,
        rssi: Int
    ) {
        guard state == .scanning else { return }
        let id = peripheral.identifier
        discovered[id] = peripheral
        let display = OlleeAdvertisement.displayName(name)
        let lastUsed = UserDefaults.standard.string(forKey: savedUUIDKey) == id.uuidString
        if let index = candidates.firstIndex(where: { $0.id == id }) {
            let existing = candidates[index]
            let resolvedName = existing.name == "Unnamed UART" && display != "Unnamed UART"
                ? display
                : existing.name
            let resolvedMatch = match.rank < existing.match.rank ? match : existing.match
            candidates[index] = BLECandidate(
                id: id,
                name: resolvedName,
                match: resolvedMatch,
                isLastUsed: lastUsed,
                rssi: max(existing.rssi, rssi)
            )
        } else {
            candidates.append(
                BLECandidate(id: id, name: display, match: match, isLastUsed: lastUsed, rssi: rssi)
            )
        }
        candidates.sort { lhs, rhs in
            if lhs.match.rank != rhs.match.rank { return lhs.match.rank < rhs.match.rank }
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func clearCandidates() {
        candidates = []
        discovered = [:]
    }

    private func fail(_ message: String) {
        lastError = message
        if state == .ready { return }
        clearCandidates()
        state = .idle
    }

    private func noteBluetoothOff() {
        central.stopScan()
        clearCandidates()
        state = .poweredOff
        lastError = "Bluetooth is off"
    }

    private func dropRadio() {
        session?.stop()
        radio?.finish()
        session = nil
        radio = nil
    }

    private func attachSession() {
        guard let peripheral, let rx else { return }
        dropRadio()
        let radio = CoreBluetoothNUS(peripheral: peripheral, rx: rx)
        self.radio = radio
        session = OlleeSession(link: radio, worldTimeHeader: storedWorldTimeHeader())
        state = .ready
        lastError = nil
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
        rssi: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        guard let match = OlleeAdvertisement.match(name: name, advertisedServices: services) else { return }
        let rssiValue = rssi.intValue
        Task { @MainActor in
            self.record(peripheral: peripheral, name: name, match: match, rssi: rssiValue)
        }
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
            self.dropRadio()
            self.rx = nil
            self.tx = nil
            if self.peripheral?.identifier == peripheral.identifier {
                self.peripheral = nil
                self.deviceName = nil
            }
            if self.state != .scanning {
                self.state = .idle
            }
            if let error, self.state != .scanning {
                self.lastError = error.localizedDescription
            }
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
