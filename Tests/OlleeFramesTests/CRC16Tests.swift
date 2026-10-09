import XCTest
@testable import OlleeFrames

final class CRC16Tests: XCTestCase {
    func testCCITTFalseReferenceVector() {
        XCTAssertEqual(CRC16.ccittFalse(Array("123456789".utf8)), 0x29B1)
    }

    func testNameTagInnerHelloSpace() {
        let inner: [UInt8] = [0x02, 0x2F] + Array("Hello ".utf8)
        XCTAssertEqual(CRC16.ccittFalse(inner), 0xC0C2)
    }
}
