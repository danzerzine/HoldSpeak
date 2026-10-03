import XCTest
@testable import HoldSpeakCore

final class TerminologyStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptt-term-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func newStore(directory: URL? = nil, language: String = "ru") -> TerminologyStore {
        TerminologyStore(directory: directory ?? tempDir(),
                         bundle: .main,
                         defaultsBundlePrefix: "nonexistent-seed",
                         legacyFlatFile: nil,
                         initialLanguage: language)
    }

    @MainActor
    func test_emptyWhenNoFileAndNoSeed() {
        XCTAssertEqual(newStore().entries, [])
    }

    @MainActor
    func test_roundTripJSON() {
        let dir = tempDir()
        let s1 = newStore(directory: dir)
        s1.add(TerminologyEntry(canonical: "pull request",
                                variants: ["пулл реквест", "пул-реквест"],
                                caseSensitive: false))
        XCTAssertEqual(s1.entries.count, 1)

        let s2 = newStore(directory: dir)
        XCTAssertEqual(s2.entries.count, 1)
        XCTAssertEqual(s2.entries.first?.canonical, "pull request")
        XCTAssertEqual(s2.entries.first?.variants, ["пулл реквест", "пул-реквест"])
    }

    @MainActor
    func test_addRemoveUpdate() {
        let store = newStore()
        let e = TerminologyEntry(canonical: "merge", variants: ["мёрдж"])
        store.add(e)
        XCTAssertEqual(store.entries.count, 1)

        var updated = store.entries[0]
        updated.variants.append("мердж")
        store.update(updated)
        XCTAssertEqual(store.entries[0].variants, ["мёрдж", "мердж"])

        store.remove(id: updated.id)
        XCTAssertEqual(store.entries.count, 0)
    }

    @MainActor
    func test_replaceAll() {
        let store = newStore()
        store.add(TerminologyEntry(canonical: "a", variants: []))
        store.add(TerminologyEntry(canonical: "b", variants: []))
        store.replaceAll([TerminologyEntry(canonical: "c", variants: [])])
        XCTAssertEqual(store.entries.map(\.canonical), ["c"])
    }

    @MainActor
    func test_perLanguageSetsAreIndependent() {
        let dir = tempDir()
        let ruStore = newStore(directory: dir, language: "ru")
        ruStore.add(TerminologyEntry(canonical: "pull request", variants: ["пулл реквест"]))

        ruStore.setActiveLanguage("uk")
        XCTAssertEqual(ruStore.entries, [], "switching to uk should show empty (no seed, no disk file)")
        ruStore.add(TerminologyEntry(canonical: "merge", variants: ["мердж"]))
        XCTAssertEqual(ruStore.entries.map(\.canonical), ["merge"])

        ruStore.setActiveLanguage("ru")
        XCTAssertEqual(ruStore.entries.map(\.canonical), ["pull request"], "ru set must persist")
    }

    @MainActor
    func test_entriesForLanguage_readsOtherSetsWithoutSwitching() {
        let dir = tempDir()
        let store = newStore(directory: dir, language: "ru")
        store.add(TerminologyEntry(canonical: "pull request", variants: []))
        store.setActiveLanguage("uk")
        store.add(TerminologyEntry(canonical: "merge", variants: []))

        let store2 = newStore(directory: dir, language: "en")
        XCTAssertEqual(store2.entries(for: "ru").map(\.canonical), ["pull request"])
        XCTAssertEqual(store2.entries(for: "uk").map(\.canonical), ["merge"])
        XCTAssertEqual(store2.activeLanguage, "en")
    }

    @MainActor
    func test_legacyFlatFileMigratesToRu() {
        let dir = tempDir()
        // Simulate legacy flat file living alongside the directory
        let legacyDir = dir.deletingLastPathComponent()
        let legacy = legacyDir.appendingPathComponent("legacy-terminology-\(UUID()).json")
        let seedEntry = TerminologyEntry(canonical: "legacy", variants: ["старый"])
        let data = try! JSONEncoder().encode([seedEntry])
        try! data.write(to: legacy)

        let store = TerminologyStore(directory: dir,
                                     bundle: .main,
                                     defaultsBundlePrefix: "nonexistent-seed",
                                     legacyFlatFile: legacy,
                                     initialLanguage: "ru")
        XCTAssertEqual(store.entries.map(\.canonical), ["legacy"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path),
                       "legacy file should be moved away")
    }

    @MainActor
    func test_addCorrection_joinsExistingTermIgnoringCase() {
        let dir = tempDir()
        let store = newStore(directory: dir)
        store.add(TerminologyEntry(canonical: "Basecamp", variants: ["бейскэмп"]))
        XCTAssertEqual(store.addCorrection(wrong: " бойскап ", right: "basecamp"),
                       .addedVariant(canonical: "Basecamp"))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].variants, ["бейскэмп", "бойскап"])
        XCTAssertEqual(store.addCorrection(wrong: "Бойскап", right: "Basecamp"), .alreadyThere)
        XCTAssertEqual(newStore(directory: dir).entries[0].variants, ["бейскэмп", "бойскап"])
    }

    @MainActor
    func test_addCorrection_newTermAndMovesSpellingFromOtherTerm() {
        let store = newStore()
        store.add(TerminologyEntry(canonical: "Jira", variants: ["джира"]))
        XCTAssertEqual(store.addCorrection(wrong: "джира", right: "Gira"), .newTerm)
        XCTAssertEqual(store.entries.first?.canonical, "Gira")
        XCTAssertEqual(store.entries.first?.variants, ["джира"])
        XCTAssertEqual(store.entries.first { $0.canonical == "Jira" }?.variants, [])
        XCTAssertEqual(store.addCorrection(wrong: "", right: "x"), .invalid)
        XCTAssertEqual(store.addCorrection(wrong: "x", right: "x"), .invalid)
    }
}
