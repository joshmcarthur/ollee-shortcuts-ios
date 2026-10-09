import XCTest
@testable import OlleeFrames

final class BeepTests: XCTestCase {
    func testPreviewInsertsPlayNowIntoCapturedReadback() throws {
        let readback = hex("00010017007E0A05C0FF0FFF")
        let frame = try Beep.previewFrame(storedReadback: readback)
        XCTAssertEqual(
            frame.encoded().map { String(format: "%02x", $0) }.joined(),
            "0013aa55d502022500010017007e0a0501c0ff0fff"
        )
    }

    func testDisabledPreviewDoesNotArmAnAlarm() throws {
        let frame = try Beep.previewFrame(storedReadback: nil)
        XCTAssertEqual(frame.payload[0], 0)
        XCTAssertEqual(frame.payload[Beep.playNowOffset], 1)
        XCTAssertEqual(frame.payload.last, 0xFF)
        XCTAssertEqual(
            frame.encoded().map { String(format: "%02x", $0) }.joined(),
            "0013aa55acb00225000000000000000001000000ff"
        )
    }

    func testReadRequestTarget() {
        XCTAssertEqual(
            Frame.read(target: Beep.readTarget).encoded().map { String(format: "%02x", $0) }.joined(),
            "0006aa55ee64022b"
        )
    }

    func testRejectsWrongReadbackLength() {
        XCTAssertThrowsError(try Beep.previewFrame(storedReadback: [0x00])) { error in
            XCTAssertEqual(error as? BeepError, .badRecord)
        }
    }
}

private func hex(_ string: String) -> [UInt8] {
    stride(from: 0, to: string.count, by: 2).compactMap { offset in
        let start = string.index(string.startIndex, offsetBy: offset)
        let end = string.index(start, offsetBy: 2)
        return UInt8(string[start..<end], radix: 16)
    }
}
