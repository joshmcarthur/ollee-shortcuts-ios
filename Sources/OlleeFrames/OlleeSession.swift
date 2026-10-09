import Foundation

public protocol NUSLink: Sendable {
    func connect() async throws
    func write(_ chunks: [[UInt8]]) async throws
    var incoming: AsyncStream<[UInt8]> { get }
}

public enum OlleeError: Error, Equatable {
    case notReady
    case timeout
    case lightUnpublished
}

/// Command façade used by the UI, App Intents, and tests. Talks only to a `NUSLink`.
public final class OlleeSession: @unchecked Sendable {
    private let link: any NUSLink
    private var ready = false
    public private(set) var worldTimeHeader: [UInt8]
    private var buffer: [UInt8] = []
    private var waiters: [UInt8: CheckedContinuation<Frame, Error>] = [:]
    private var pump: Task<Void, Never>?
    private let lock = NSLock()

    public init(link: any NUSLink, worldTimeHeader: [UInt8] = [0, 0, 0, 0]) {
        self.link = link
        self.worldTimeHeader = worldTimeHeader
    }

    public func connect() async throws {
        try await link.connect()
        ready = true
        pump = Task { [weak self] in
            guard let self else { return }
            for await chunk in self.link.incoming {
                self.ingest(chunk)
            }
        }
        await Task.yield()
    }

    public func setNameTag(_ text: String) async throws {
        try await send(try NameTag.frame(text: text))
    }

    public func beep() async throws {
        let reply = try await request(Frame.read(target: Beep.readTarget), expecting: Beep.readTarget &+ 0x20)
        try await send(try Beep.previewFrame(storedReadback: reply.payload))
    }

    public func setClockCounter(_ count: Int) async throws {
        let reply = try? await request(
            Frame.read(target: ClockCounter.readTarget),
            expecting: ClockCounter.readTarget &+ 0x20
        )
        if let header = reply?.payload.prefix(ClockCounter.headerSize), header.count == ClockCounter.headerSize {
            worldTimeHeader = Array(header)
        }
        try await send(try ClockCounter.frame(count: count, worldTimeHeader: worldTimeHeader))
    }

    public func showLight(red: UInt8, green: UInt8, blue: UInt8) async throws {
        do {
            _ = try Light.show(red: red, green: green, blue: blue)
        } catch LightError.registerUnpublished {
            throw OlleeError.lightUnpublished
        }
    }

    private func send(_ frame: Frame) async throws {
        guard ready else { throw OlleeError.notReady }
        try await link.write(Frame.attChunks(frame.encoded()))
    }

    private func request(_ frame: Frame, expecting target: UInt8) async throws -> Frame {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            waiters[target] = continuation
            lock.unlock()
            Task {
                do {
                    try await self.send(frame)
                } catch {
                    self.failWaiter(target, error)
                }
            }
            Task {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                self.failWaiter(target, OlleeError.timeout)
            }
        }
    }

    private func failWaiter(_ target: UInt8, _ error: Error) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: target)
        lock.unlock()
        waiter?.resume(throwing: error)
    }

    private func ingest(_ chunk: [UInt8]) {
        lock.lock()
        buffer += chunk
        var delivered: CheckedContinuation<Frame, Error>?
        var parsed: Frame?
        while buffer.count >= 2 {
            let total = 2 + Int(buffer[1])
            guard buffer.count >= total else { break }
            let bytes = Array(buffer.prefix(total))
            buffer.removeFirst(total)
            guard let frame = Frame.parse(bytes) else { continue }
            if let waiter = waiters.removeValue(forKey: frame.target) {
                delivered = waiter
                parsed = frame
                break
            }
        }
        lock.unlock()
        if let delivered, let parsed {
            delivered.resume(returning: parsed)
        }
    }
}
