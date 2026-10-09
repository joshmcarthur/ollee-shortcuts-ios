import XCTest
@testable import OlleeFrames

/// Byte-pipe fake: records full UART payloads and replies by read target.
final class FakeNUS: NUSLink {
    private(set) var writes: [[UInt8]] = []
    var replies: [UInt8: [UInt8]] = [:]
    var writeError: OlleeError?
    private let continuation: AsyncStream<[UInt8]>.Continuation
    let incoming: AsyncStream<[UInt8]>

    static let alarmReadback: [UInt8] = [
        0x00, 0x01, 0x00, 0x17, 0x00, 0x7E, 0x0A, 0x05, 0xC0, 0xFF, 0x0F, 0xFF,
    ]
    static let weekdayReadback: [UInt8] = [0x00, 0x00, 0x7E, 0x90] + Array("MOTUWETHFRSASU".utf8)

    init() {
        var cont: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream { cont = $0 }
        continuation = cont
    }

    func write(_ bytes: [UInt8]) async throws {
        if let writeError { throw writeError }
        writes.append(bytes)
        guard let frame = Frame.parse(bytes), let payload = replies[frame.target] else { return }
        let encoded = Frame(target: frame.target &+ 0x20, payload: payload).encoded()
        for piece in Frame.attChunks(encoded) {
            continuation.yield(piece)
        }
    }
}

@MainActor
final class OlleeSessionTests: XCTestCase {
    func testNameTagWritesEncodedFrame() async throws {
        let radio = FakeNUS()
        try await OlleeSession(link: radio).setNameTag("Hello")
        XCTAssertEqual(radio.writes, [try NameTag.frame(text: "Hello").encoded()])
    }

    func testBeepReadsAlarmThenWritesPreviewFromThatReadback() async throws {
        let radio = FakeNUS()
        radio.replies[Beep.readTarget] = FakeNUS.alarmReadback
        try await OlleeSession(link: radio).beep()

        XCTAssertEqual(radio.writes.count, 2)
        XCTAssertEqual(radio.writes[0], Frame.read(target: Beep.readTarget).encoded())
        XCTAssertEqual(
            radio.writes[1],
            try Beep.previewFrame(storedReadback: FakeNUS.alarmReadback).encoded()
        )
    }

    func testClockCounterUsesHeaderFromReadback() async throws {
        let radio = FakeNUS()
        radio.replies[ClockCounter.readTarget] = FakeNUS.weekdayReadback
        let session = OlleeSession(link: radio)
        let header = Array(FakeNUS.weekdayReadback.prefix(ClockCounter.headerSize))

        try await session.setClockCounter(0)
        XCTAssertEqual(radio.writes[0], Frame.read(target: ClockCounter.readTarget).encoded())
        XCTAssertEqual(
            radio.writes[1],
            try ClockCounter.frame(count: 0, worldTimeHeader: header).encoded()
        )

        try await session.setClockCounter(7)
        XCTAssertEqual(
            radio.writes.last,
            try ClockCounter.frame(count: 7, worldTimeHeader: header).encoded()
        )
        XCTAssertEqual(session.worldTimeHeader, header)
    }

    func testClockWriteKeepsSeededHeaderWhenReadTimesOut() async throws {
        let radio = FakeNUS()
        let header: [UInt8] = [0xFF, 0xFF, 0xAB, 0xA0]
        let session = OlleeSession(link: radio, worldTimeHeader: header, replyTimeoutNanoseconds: 10_000_000)
        try await session.setClockCounter(1)
        XCTAssertEqual(radio.writes.count, 2)
        XCTAssertEqual(
            radio.writes[1],
            try ClockCounter.frame(count: 1, worldTimeHeader: header).encoded()
        )
    }

    func testLightFailsClosedWithNoNUSWrite() async {
        let radio = FakeNUS()
        do {
            try await OlleeSession(link: radio).showLight(red: 255, green: 0, blue: 0)
            XCTFail("light must fail closed")
        } catch OlleeError.lightUnpublished {
            XCTAssertTrue(radio.writes.isEmpty)
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testWriteErrorSurfacesFromLink() async {
        let radio = FakeNUS()
        radio.writeError = .notReady
        do {
            try await OlleeSession(link: radio).setNameTag("Hi")
            XCTFail("expected notReady")
        } catch OlleeError.notReady {
            return
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testBeepTimesOutWhenNoReply() async {
        let radio = FakeNUS()
        do {
            try await OlleeSession(link: radio, replyTimeoutNanoseconds: 10_000_000).beep()
            XCTFail("expected timeout")
        } catch OlleeError.timeout {
            XCTAssertEqual(radio.writes, [Frame.read(target: Beep.readTarget).encoded()])
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testStaleTimeoutDoesNotFailTheNextBeep() async throws {
        let radio = FakeNUS()
        let session = OlleeSession(link: radio, replyTimeoutNanoseconds: 10_000_000)
        do {
            try await session.beep()
            XCTFail("first beep should time out")
        } catch OlleeError.timeout {}

        radio.replies[Beep.readTarget] = FakeNUS.alarmReadback
        try await session.beep()
        XCTAssertEqual(
            radio.writes.last,
            try Beep.previewFrame(storedReadback: FakeNUS.alarmReadback).encoded()
        )
    }

    func testStopFailsInFlightRequest() async {
        let radio = FakeNUS()
        let session = OlleeSession(link: radio, replyTimeoutNanoseconds: 5_000_000_000)
        async let beep: Void = session.beep()
        while radio.writes.isEmpty {
            await Task.yield()
        }
        session.stop()
        do {
            try await beep
            XCTFail("expected notReady")
        } catch OlleeError.notReady {
            return
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
