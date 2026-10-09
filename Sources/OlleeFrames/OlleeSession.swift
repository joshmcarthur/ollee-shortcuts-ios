import Foundation

public protocol NUSLink: AnyObject {
    func write(_ bytes: [UInt8]) async throws
    var incoming: AsyncStream<[UInt8]> { get }
}

public enum OlleeError: Error, Equatable {
    case notReady
    case timeout
    case lightUnpublished
}

/// Command façade for UI, App Intents, and tests. Talks only to a byte-pipe `NUSLink`.
@MainActor
public final class OlleeSession {
    private let link: any NUSLink
    public private(set) var worldTimeHeader: [UInt8]
    private let replyTimeoutNanoseconds: UInt64
    private var assembler = Frame.Assembler()
    private var waiters: [UInt8: CheckedContinuation<Frame, Error>] = [:]
    private var timeouts: [UInt8: Task<Void, Never>] = [:]
    private var pump: Task<Void, Never>?

    public init(
        link: any NUSLink,
        worldTimeHeader: [UInt8] = [0, 0, 0, 0],
        replyTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.link = link
        self.worldTimeHeader = worldTimeHeader
        self.replyTimeoutNanoseconds = replyTimeoutNanoseconds
        let incoming = link.incoming
        pump = Task { @MainActor [weak self] in
            for await chunk in incoming {
                self?.ingest(chunk)
            }
        }
    }

    public func stop() {
        pump?.cancel()
        pump = nil
        for target in Array(waiters.keys) {
            failWaiter(target, OlleeError.notReady)
        }
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
        if let header = reply?.payload.prefix(ClockCounter.headerSize),
           header.count == ClockCounter.headerSize {
            worldTimeHeader = Array(header)
        }
        try await send(try ClockCounter.frame(count: count, worldTimeHeader: worldTimeHeader))
    }

    public func showLight(red: UInt8, green: UInt8, blue: UInt8) async throws {
        do {
            try await send(try Light.show(red: red, green: green, blue: blue))
        } catch LightError.registerUnpublished {
            throw OlleeError.lightUnpublished
        }
    }

    private func send(_ frame: Frame) async throws {
        try await link.write(frame.encoded())
    }

    private func request(_ frame: Frame, expecting target: UInt8) async throws -> Frame {
        try await withCheckedThrowingContinuation { continuation in
            failWaiter(target, OlleeError.timeout)
            waiters[target] = continuation
            let timeout = replyTimeoutNanoseconds
            timeouts[target] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeout)
                guard !Task.isCancelled else { return }
                self?.failWaiter(target, OlleeError.timeout)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.send(frame)
                } catch {
                    self.failWaiter(target, error)
                }
            }
        }
    }

    private func failWaiter(_ target: UInt8, _ error: Error) {
        timeouts.removeValue(forKey: target)?.cancel()
        waiters.removeValue(forKey: target)?.resume(throwing: error)
    }

    private func ingest(_ chunk: [UInt8]) {
        for frame in assembler.push(chunk) {
            timeouts.removeValue(forKey: frame.target)?.cancel()
            waiters.removeValue(forKey: frame.target)?.resume(returning: frame)
        }
    }
}
