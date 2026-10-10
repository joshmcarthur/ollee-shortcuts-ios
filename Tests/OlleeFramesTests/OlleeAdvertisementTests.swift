import XCTest
@testable import OlleeFrames

final class OlleeAdvertisementTests: XCTestCase {
    private let nus = OlleeAdvertisement.nordicUARTService

    func testOlleeNameIsLikelyMatchWithoutUART() {
        XCTAssertEqual(
            OlleeAdvertisement.match(name: "Ollee Watch", advertisedServices: []),
            .likelyOllee
        )
    }

    func testCRSNameIsLikelyMatch() {
        XCTAssertEqual(
            OlleeAdvertisement.match(name: "crs", advertisedServices: []),
            .likelyOllee
        )
    }

    func testUARTWithoutOlleeNameIsGenericCandidate() {
        XCTAssertEqual(
            OlleeAdvertisement.match(name: "nRF UART", advertisedServices: [nus.lowercased()]),
            .nordicUART
        )
    }

    func testUnrelatedNameWithoutUARTIsDropped() {
        XCTAssertNil(OlleeAdvertisement.match(name: "Pixel Buds", advertisedServices: []))
    }

    func testCRSPrefixWithoutExactNameIsDropped() {
        XCTAssertNil(OlleeAdvertisement.match(name: "CRS-01", advertisedServices: []))
    }

    func testLikelyNamesRankAboveGenericUART() {
        let watch = OlleeAdvertisement.match(name: "OLLEE", advertisedServices: [])
        let uart = OlleeAdvertisement.match(name: "Adafruit", advertisedServices: [nus])
        XCTAssertEqual(watch, .likelyOllee)
        XCTAssertEqual(uart, .nordicUART)
        XCTAssertLessThan(try XCTUnwrap(watch).rank, try XCTUnwrap(uart).rank)
    }

    func testBlankUARTNameDisplaysPlaceholder() {
        XCTAssertEqual(OlleeAdvertisement.match(name: "  ", advertisedServices: [nus]), .nordicUART)
        XCTAssertEqual(OlleeAdvertisement.displayName("  "), "Unnamed UART")
        XCTAssertEqual(OlleeAdvertisement.displayName("CRS"), "CRS")
    }
}
