import XCTest
@testable import HoldSpeakCore

final class InputSelectionTests: XCTestCase {
    func testRawValueRoundTrip() {
        for s in [InputSelection.systemDefault, .avoidBluetooth, .device(uid: "AC-07-75:input")] {
            XCTAssertEqual(InputSelection(rawValue: s.rawValue), s)
        }
    }

    func testUnknownOrEmptyFallsBackToAvoidBluetooth() {
        XCTAssertEqual(InputSelection(rawValue: ""), .avoidBluetooth)
        XCTAssertEqual(InputSelection(rawValue: "garbage"), .avoidBluetooth)
    }
}
