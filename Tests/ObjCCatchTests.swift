import XCTest
import ObjCCatch

final class ObjCCatchTests: XCTestCase {
    func testConvertsRaisedExceptionToError() {
        var error: NSError?
        let ok = HSCatchObjCException({
            NSException(name: .invalidArgumentException, reason: "boom", userInfo: nil).raise()
        }, &error)
        XCTAssertFalse(ok)
        XCTAssertEqual(error?.localizedDescription, "boom")
    }

    func testPassesThroughWhenNothingRaised() {
        var ran = false
        XCTAssertTrue(HSCatchObjCException({ ran = true }, nil))
        XCTAssertTrue(ran)
    }
}
