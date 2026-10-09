import XCTest
@testable import OlleeFrames

/// Loopback NUS: fake peripheral that records ATT writes and replies to reads.
final class LoopbackNUS: NUSLink, @unchecked Sendable {
    private(set) var chunks: [[UInt8]] = []
    private(set) var frames: [Frame] = []
    private var assemble: [UInt8] = []
    private let continuation: AsyncStream<[UInt8]>.Continuation
    let incoming: AsyncStream<[UInt8]>
    private(set) var didConnect = false

    /// Captured 12-byte alarm read-back (`02 2B` → `4B`).
    static let alarmReadback: [UInt8] = [
        0x00, 0x01, 0x00, 0x17, 0x00, 0x7E, 0x0A, 0x05, 0xC0, 0xFF, 0x0F, 0xFF,
    ]
    /// World Time +9h header plus default weekday names.
    static let weekdayReadback: [UInt8] = [0x00, 0x00, 0x7E, 0x90] + Array("MOTUWETHFRSASU".utf8)

    init() {
        var cont: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream(bufferingPolicy: .bufferingOldest(16)) { cont = $0 }
        continuation = cont
    }

    func connect() async throws {
        didConnect = true
    }

    func write(_ chunks: [[UInt8]]) async throws {
        self.chunks.append(contentsOf: chunks)
        for chunk in chunks {
            assemble += chunk
            while assemble.count >= 2 {
                let total = 2 + Int(assemble[1])
                guard assemble.count >= total else { break }
                let bytes = Array(assemble.prefix(total))
                assemble.removeFirst(total)
                guard let frame = Frame.parse(bytes) else { continue }
                frames.append(frame)
                replyIfRead(frame)
            }
        }
    }

    private func replyIfRead(_ frame: Frame) {
        guard frame.payload.isEmpty else { return }
        let payload: [UInt8]
        if frame.target == Beep.readTarget {
            payload = Self.alarmReadback
        } else if frame.target == ClockCounter.readTarget {
            payload = Self.weekdayReadback
        } else {
            return
        }
        let reply = Frame(target: frame.target &+ 0x20, payload: payload)
        for piece in Frame.attChunks(reply.encoded()) {
            continuation.yield(piece)
        }
    }
}

final class OlleeSessionTests: XCTestCase {
    func testNameTagGoesThroughConnectedClientAsNUSChunks() async throws {
        let radio = LoopbackNUS()
        let client = OlleeSession(link: radio)
        try await client.connect()
        XCTAssertTrue(radio.didConnect)

        try await client.setNameTag("Hello")

        XCTAssertFalse(radio.chunks.isEmpty)
        XCTAssertTrue(radio.chunks.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(radio.chunks.flatMap { $0 }, try NameTag.frame(text: "Hello").encoded())
        XCTAssertEqual(
            radio.frames.last?.encoded().map { String(format: "%02x", $0) }.joined(),
            "000caa55c0c2022f48656c6c6f20"
        )
    }

    func testBeepReadsAlarmThenWritesPlayNowPreview() async throws {
        let radio = LoopbackNUS()
        let client = OlleeSession(link: radio)
        try await client.connect()

        try await client.beep()

        XCTAssertEqual(radio.frames.count, 2)
        XCTAssertEqual(radio.frames[0].target, Beep.readTarget)
        XCTAssertTrue(radio.frames[0].payload.isEmpty)
        XCTAssertEqual(
            radio.frames[1].encoded().map { String(format: "%02x", $0) }.joined(),
            "0013aa55d502022500010017007e0a0501c0ff0fff"
        )
        XCTAssertTrue(radio.chunks.allSatisfy { $0.count <= 20 })
        XCTAssertGreaterThan(radio.chunks.count, 1)
    }

    func testClockCounterZeroAndSevenPreserveWorldTimeHeader() async throws {
        let radio = LoopbackNUS()
        let client = OlleeSession(link: radio)
        try await client.connect()

        try await client.setClockCounter(0)
        XCTAssertEqual(radio.frames[0].target, ClockCounter.readTarget)
        XCTAssertEqual(
            radio.frames[1].encoded().map { String(format: "%02x", $0) }.joined(),
            "0018aa558410023400007e902030203020302030203020302030"
        )

        try await client.setClockCounter(7)
        XCTAssertEqual(
            radio.frames.last?.encoded().map { String(format: "%02x", $0) }.joined(),
            "0018aa555de9023400007e902037203720372037203720372037"
        )
        XCTAssertTrue(radio.chunks.allSatisfy { $0.count <= 20 })
    }

    func testLightFailsClosedWithNoNUSWrite() async throws {
        let radio = LoopbackNUS()
        let client = OlleeSession(link: radio)
        try await client.connect()

        do {
            try await client.showLight(red: 255, green: 0, blue: 0)
            XCTFail("light must fail closed")
        } catch OlleeError.lightUnpublished {
            XCTAssertTrue(radio.frames.isEmpty)
            XCTAssertTrue(radio.chunks.isEmpty)
        }
    }

    func testCommandsNeedConnect() async {
        let client = OlleeSession(link: LoopbackNUS())
        do {
            try await client.setNameTag("Hi")
            XCTFail("expected notReady")
        } catch OlleeError.notReady {
            return
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
