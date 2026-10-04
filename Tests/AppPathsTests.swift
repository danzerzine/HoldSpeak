import XCTest
@testable import HoldSpeakCore

final class AppPathsTests: XCTestCase {
    private func tempBase() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("speak-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func freshDefaults() -> UserDefaults {
        let name = "speak-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_movesHoldSpeakFolderWithContents() throws {
        let base = try tempBase()
        let old = base.appendingPathComponent("HoldSpeak")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("db".utf8).write(to: old.appendingPathComponent("history.sqlite"))

        XCTAssertEqual(try AppPaths.migrateSupportDirectory(base: base), "HoldSpeak")
        let moved = base.appendingPathComponent("Speak/history.sqlite")
        XCTAssertEqual(try Data(contentsOf: moved), Data("db".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func test_fallsBackToPushToTalkFolder() throws {
        let base = try tempBase()
        try FileManager.default.createDirectory(at: base.appendingPathComponent("push-to-talk"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(try AppPaths.migrateSupportDirectory(base: base), "push-to-talk")
    }

    func test_existingSpeakFolderIsLeftAlone() throws {
        let base = try tempBase()
        for name in ["Speak", "HoldSpeak"] {
            try FileManager.default.createDirectory(at: base.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
        XCTAssertNil(try AppPaths.migrateSupportDirectory(base: base))
        XCTAssertTrue(FileManager.default.fileExists(atPath: base.appendingPathComponent("HoldSpeak").path))
    }

    func test_copiesOldSettingsOnce_keepingNewOnes() {
        let d = freshDefaults()
        d.set("en", forKey: "primaryLanguage")
        let old: [String: Any] = ["primaryLanguage": "ru", "launchAtLogin": true, "modelID": "turbo"]

        XCTAssertTrue(AppPaths.migrateDefaults(from: old, into: d))
        XCTAssertEqual(d.string(forKey: "primaryLanguage"), "en")
        XCTAssertTrue(d.bool(forKey: "launchAtLogin"))
        XCTAssertEqual(d.string(forKey: "modelID"), "turbo")

        d.removeObject(forKey: "modelID")
        XCTAssertFalse(AppPaths.migrateDefaults(from: old, into: d))
        XCTAssertNil(d.string(forKey: "modelID"))
    }

    func test_noOldSettings_marksDoneWithoutCopying() {
        let d = freshDefaults()
        XCTAssertFalse(AppPaths.migrateDefaults(from: [:], into: d))
        XCTAssertFalse(AppPaths.migrateDefaults(from: ["modelID": "turbo"], into: d))
        XCTAssertNil(d.string(forKey: "modelID"))
    }
}
