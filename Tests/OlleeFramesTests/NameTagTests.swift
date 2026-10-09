import XCTest
@testable import OlleeFrames

final class NameTagTests: XCTestCase {
    func testHelloPadsToCapturedFreeOlleeFrame() throws {
        let frame = try NameTag.frame(text: "Hello")
        XCTAssertEqual(
            frame.encoded(),
            [0x00, 0x0C, 0xAA, 0x55, 0xC0, 0xC2, 0x02, 0x2F, 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20]
        )
    }

    func testClampsToSixASCIIAndPads() throws {
        let frame = try NameTag.frame(text: "TOOLONG!")
        XCTAssertEqual(frame.payload, Array("TOOLON".utf8))
    }

    func testRejectsNonASCII() {
        XCTAssertThrowsError(try NameTag.frame(text: "café")) { error in
            XCTAssertEqual(error as? NameTagError, .notASCII)
        }
    }

    func testShortValuePadsWithSpaces() throws {
        let frame = try NameTag.frame(text: "Hi")
        XCTAssertEqual(frame.payload, Array("Hi    ".utf8))
    }

    func testParseRoundTrip() throws {
        let encoded = try NameTag.frame(text: "OLLEE").encoded()
        let parsed = try XCTUnwrap(Frame.parse(encoded))
        XCTAssertEqual(parsed.target, NameTag.target)
        XCTAssertEqual(parsed.payload, Array("OLLEE ".utf8))
    }

    func testParseCapturedTemperatureReadback() throws {
        let bytes = hex("000CAA55CB6D024E202035342046")
        let parsed = try XCTUnwrap(Frame.parse(bytes))
        XCTAssertEqual(parsed.command, 0x02)
        XCTAssertEqual(parsed.target, 0x4E)
        XCTAssertEqual(String(bytes: parsed.payload, encoding: .ascii), " 54 F")
    }

    func testParseRejectsBadMagic() {
        XCTAssertNil(Frame.parse([0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x02, 0x2A]))
    }

    func testATTChunksSplitAtTwentyBytes() {
        let bytes = Array(0..<25 as Range<UInt8>)
        let chunks = Frame.attChunks(bytes)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 20)
        XCTAssertEqual(chunks[1], [20, 21, 22, 23, 24])
    }
}

private func hex(_ string: String) -> [UInt8] {
    stride(from: 0, to: string.count, by: 2).compactMap { offset in
        let start = string.index(string.startIndex, offsetBy: offset)
        let end = string.index(start, offsetBy: 2)
        return UInt8(string[start..<end], radix: 16)
    }
}
