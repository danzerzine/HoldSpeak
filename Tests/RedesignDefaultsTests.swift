import XCTest
@testable import HoldSpeakCore

final class RedesignDefaultsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "RedesignDefaultsTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testNewInstallGetsGlassUnderIcon() {
        let d = freshDefaults()
        PreferencesStore.shared.migrateRedesignDefaults(d)
        XCTAssertEqual(d.string(forKey: "pillColor"), "glass")
        XCTAssertNil(d.string(forKey: "hudPosition")) // the new default, under the icon
    }

    func testExistingInstallKeepsBlackPillAtBottom() {
        let d = freshDefaults()
        d.set("whisper", forKey: "transcriptionEngine")
        PreferencesStore.shared.migrateRedesignDefaults(d)
        XCTAssertEqual(d.string(forKey: "pillColor"), "black")
        XCTAssertEqual(d.string(forKey: "hudPosition"), HUDPosition.bottomCenter.rawValue)
    }

    func testExistingChoiceOfPositionIsKept() {
        let d = freshDefaults()
        d.set(HUDPosition.underMenuBarIcon.rawValue, forKey: "hudPosition")
        PreferencesStore.shared.migrateRedesignDefaults(d)
        XCTAssertEqual(d.string(forKey: "hudPosition"), HUDPosition.underMenuBarIcon.rawValue)
        XCTAssertEqual(d.string(forKey: "pillColor"), "black")
    }

    func testRunsOnce() {
        let d = freshDefaults()
        d.set("graphite", forKey: "pillColor")
        d.set("whisper", forKey: "transcriptionEngine")
        PreferencesStore.shared.migrateRedesignDefaults(d)
        XCTAssertEqual(d.string(forKey: "pillColor"), "graphite")
        XCTAssertNil(d.string(forKey: "hudPosition"))
    }
}
