import XCTest
import GRDB
@testable import HoldSpeakCore

final class HistoryStoreTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pt-test-\(UUID().uuidString).sqlite")
        return try HistoryStore(url: url)
    }

    func test_appendAndFetchRecent() throws {
        let store = try makeStore()
        _ = try store.append(.init(createdAt: 1, rawText: "a", cleanedText: "A.", durationMs: 1000, wordCount: 1, language: "ru", inserted: true))
        _ = try store.append(.init(createdAt: 2, rawText: "b", cleanedText: "B.", durationMs: 2000, wordCount: 2, language: "ru", inserted: true))
        let recent = try store.recent(limit: 10)
        XCTAssertEqual(recent.map(\.cleanedText), ["B.", "A."])
    }

    func test_totalWords() throws {
        let store = try makeStore()
        for (i, wc) in [1, 2, 3].enumerated() {
            _ = try store.append(.init(createdAt: Int64(i), rawText: "", cleanedText: "", durationMs: 1000, wordCount: wc, language: nil, inserted: true))
        }
        XCTAssertEqual(try store.totalWords(), 6)
    }

    func test_sumsSince_excludesOlder() throws {
        let store = try makeStore()
        _ = try store.append(.init(createdAt: 100, rawText: "", cleanedText: "", durationMs: 1000, wordCount: 5, language: nil, inserted: true))
        _ = try store.append(.init(createdAt: 200, rawText: "", cleanedText: "", durationMs: 2000, wordCount: 10, language: nil, inserted: true))
        let s = try store.sumsSince(150)
        XCTAssertEqual(s.words, 10)
        XCTAssertEqual(s.durationMs, 2000)
    }

    func test_clear() throws {
        let store = try makeStore()
        _ = try store.append(.init(createdAt: 1, rawText: "", cleanedText: "", durationMs: 1, wordCount: 1, language: nil, inserted: true))
        try store.clear()
        XCTAssertEqual(try store.recent(limit: 10).count, 0)
    }

    private func rec(_ t: Int64, words: Int = 1, ms: Int = 1000) -> TranscriptionRecord {
        .init(createdAt: t, rawText: "", cleanedText: "", durationMs: ms, wordCount: words, language: nil, inserted: true)
    }

    func test_metricsKeepGrowingPastHistoryCap() throws {
        let store = try makeStore()
        let n = HistoryStore.maxEntries + 50
        for i in 1...n { _ = try store.append(rec(Int64(i), words: 2, ms: 500)) }
        XCTAssertEqual(try store.recent(limit: 1000).count, HistoryStore.maxEntries)
        XCTAssertEqual(try store.totalWords(), n * 2)
        let s = try store.sumsSince(0)
        XCTAssertEqual(s.words, n * 2)
        XCTAssertEqual(s.durationMs, n * 500)
        // Window queries also see pruned rows.
        XCTAssertEqual(try store.sumsSince(10).words, (n - 10) * 2)
    }

    func test_clearKeepsMetrics() throws {
        let store = try makeStore()
        _ = try store.append(rec(1, words: 3))
        _ = try store.append(rec(2, words: 4))
        try store.clear()
        XCTAssertEqual(try store.recent(limit: 10).count, 0)
        XCTAssertEqual(try store.totalWords(), 7)
        _ = try store.append(rec(3, words: 5))
        XCTAssertEqual(try store.totalWords(), 12)
        XCTAssertEqual(try store.recent(limit: 10).count, 1)
    }

    func test_migrationBackfillsStatsFromExistingHistory() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pt-test-\(UUID().uuidString).sqlite")
        // Simulate a pre-v2 database: only the v1 schema with some rows.
        do {
            let q = try DatabaseQueue(path: url.path)
            var m = DatabaseMigrator()
            m.registerMigration("v1") { db in
                try db.create(table: "transcriptions") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("createdAt", .integer).notNull().indexed()
                    t.column("rawText", .text).notNull()
                    t.column("cleanedText", .text).notNull()
                    t.column("durationMs", .integer).notNull()
                    t.column("wordCount", .integer).notNull()
                    t.column("language", .text)
                    t.column("inserted", .boolean).notNull().defaults(to: false)
                }
            }
            try m.migrate(q)
            try q.write { db in
                var a = self.rec(1, words: 3, ms: 100); try a.insert(db)
                var b = self.rec(2, words: 4, ms: 200); try b.insert(db)
            }
        }
        let store = try HistoryStore(url: url)
        XCTAssertEqual(try store.totalWords(), 7)
        XCTAssertEqual(try store.sumsSince(0).durationMs, 300)
    }
}
