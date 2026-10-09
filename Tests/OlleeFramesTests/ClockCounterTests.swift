import XCTest
@testable import OlleeFrames

final class ClockCounterTests: XCTestCase {
    private let captureHeader: [UInt8] = [0x00, 0x00, 0x7E, 0x90]

    func testCounterThreeReplacesWeekdaySlotsAndKeepsWorldTimeHeader() throws {
        let frame = try ClockCounter.frame(count: 3, worldTimeHeader: captureHeader)
        XCTAssertEqual(
            frame.encoded().map { String(format: "%02x", $0) }.joined(),
            "0018aa554168023400007e902033203320332033203320332033"
        )
    }

    func testClampsOutsideZeroThroughSeven() throws {
        let high = try ClockCounter.frame(count: 99, worldTimeHeader: captureHeader)
        let low = try ClockCounter.frame(count: -4, worldTimeHeader: captureHeader)
        XCTAssertEqual(String(bytes: Array(high.payload.dropFirst(4)), encoding: .ascii), " 7 7 7 7 7 7 7")
        XCTAssertEqual(String(bytes: Array(low.payload.dropFirst(4)), encoding: .ascii), " 0 0 0 0 0 0 0")
    }

    func testPreservesNonTokyoWorldTimeHeader() throws {
        let header: [UInt8] = [0xFF, 0xFF, 0xAB, 0xA0]
        let frame = try ClockCounter.frame(count: 1, worldTimeHeader: header)
        XCTAssertEqual(Array(frame.payload.prefix(4)), header)
    }

    func testReadRequestTarget() {
        XCTAssertEqual(
            Frame.read(target: ClockCounter.readTarget).encoded().map { String(format: "%02x", $0) }.joined(),
            "0006aa551d9b0235"
        )
    }

    func testRejectsWrongHeaderSize() {
        XCTAssertThrowsError(try ClockCounter.frame(count: 1, worldTimeHeader: [0x00])) { error in
            XCTAssertEqual(error as? ClockCounterError, .badHeader)
        }
    }
}
