import XCTest
@testable import HoldSpeakCore

/// Stands in for the metrics side of `HistoryStore` (the unpruned `utterance_stats`
/// table), so sums here are independent of the 100-entry history cap.
private final class MockStore: HistoryStoring {
    var recentSums: (Int, Int) = (0, 0)
    func append(_ record: TranscriptionRecord) throws -> TranscriptionRecord { record }
    func recent(limit: Int) throws -> [TranscriptionRecord] { [] }
    func sumsSince(_ unixMs: Int64) throws -> (words: Int, durationMs: Int) { recentSums }
    func count(fromMs: Int64, toMs: Int64) throws -> Int { 0 }
    func clear() throws {}
}

final class MetricsEngineTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func makeStore() throws -> HistoryStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pt-test-\(UUID().uuidString).sqlite")
        return try HistoryStore(url: url)
    }

    private func add(_ store: HistoryStore, at date: Date, words: Int = 10, durationMs: Int = 6000) throws {
        _ = try store.append(.init(createdAt: Int64(date.timeIntervalSince1970 * 1000), rawText: "", cleanedText: "",
                                   durationMs: durationMs, wordCount: words, language: nil, inserted: true))
    }

    func test_computesWpm() throws {
        let s = MockStore()
        s.recentSums = (1280, 600_000) // 1280 words in 10 minutes → 128 wpm
        XCTAssertEqual(try MetricsEngine(store: s).current().wpm7d, 128)
    }

    func test_zeroDurationGivesZeroWpm() throws {
        XCTAssertEqual(try MetricsEngine(store: MockStore()).current().wpm7d, 0)
    }

    func test_countsTodayAndYesterdayByCalendarDay() throws {
        let store = try makeStore()
        let now = ISO8601DateFormatter().date(from: "2026-10-03T10:00:00Z")!
        try add(store, at: now.addingTimeInterval(-60))                 // today
        try add(store, at: now.addingTimeInterval(-9 * 3600))           // 01:00 today
        try add(store, at: now.addingTimeInterval(-10 * 3600 - 1))      // 23:59:59 yesterday
        try add(store, at: now.addingTimeInterval(-33 * 3600))          // 01:00 yesterday
        try add(store, at: now.addingTimeInterval(-35 * 3600))          // two days ago
        let m = try MetricsEngine(store: store, calendar: utc).current(now: now)
        XCTAssertEqual(m.dictationsToday, 2)
        XCTAssertEqual(m.dictationsYesterday, 2)
    }

    func test_resetAnchorHidesEarlierDictations() throws {
        let store = try makeStore()
        let now = ISO8601DateFormatter().date(from: "2026-10-03T10:00:00Z")!
        try add(store, at: now.addingTimeInterval(-3600))
        try add(store, at: now.addingTimeInterval(-60))
        let anchor = Int64(now.addingTimeInterval(-1800).timeIntervalSince1970 * 1000)
        let m = try MetricsEngine(store: store, resetAnchor: { anchor }, calendar: utc).current(now: now)
        XCTAssertEqual(m.dictationsToday, 1)
        XCTAssertEqual(m.dictationsYesterday, 0)
    }

    func test_realStore_countsNotCappedByHistoryPruning() throws {
        let store = try makeStore()
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let n = HistoryStore.maxEntries * 2
        for i in 0..<n {
            _ = try store.append(.init(createdAt: nowMs - Int64(n - i), rawText: "", cleanedText: "",
                                       durationMs: 60_000, wordCount: 100, language: nil, inserted: true))
        }
        try store.clear() // clearing history must not reset metrics
        let m = try MetricsEngine(store: store).current(now: now)
        XCTAssertEqual(m.wpm7d, 100)
        // All were appended within the last second; unless that straddles midnight they count as today.
        XCTAssertEqual(m.dictationsToday + m.dictationsYesterday, n)
    }
}
