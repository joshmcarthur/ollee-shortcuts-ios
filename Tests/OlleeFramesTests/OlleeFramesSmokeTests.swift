import XCTest
@testable import OlleeFrames

final class OlleeFramesSmokeTests: XCTestCase {
    func testModuleExists() {
        XCTAssertEqual(String(describing: OlleeFrames.self), "OlleeFrames")
    }
}
