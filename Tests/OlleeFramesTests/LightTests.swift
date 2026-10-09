import XCTest
@testable import OlleeFrames

final class LightTests: XCTestCase {
    func testRGBRegisterIsUnpublished() {
        XCTAssertFalse(Light.registerPublished)
    }

    func testShowThrowsUntilAGoldenVectorExists() {
        XCTAssertThrowsError(try Light.show(red: 255, green: 0, blue: 0)) { error in
            XCTAssertEqual(error as? LightError, .registerUnpublished)
        }
    }
}
