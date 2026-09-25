import XCTest
@testable import HoldSpeakCore

/// Stands in for the metrics side of `HistoryStore` (the unpruned `utterance_stats`
/// table), so sums here are independent of the 100-entry history cap.
private final class MockStore: HistoryStoring {
    /// Returned for `sumsSince(0)` — the "since reset anchor" total query.
    var totalSums: (Int, Int) = (0, 0)
    /// Returned for any non-zero anchor — the trailing-7-days query.
    var recentSums: (Int, Int) = (0, 0)
    func append(_ record: TranscriptionRecord) throws -> TranscriptionRecord { record }
    func recent(limit: Int) throws -> [TranscriptionRecord] { [] }
    func totalWords() throws -> Int { totalSums.0 }
    func sumsSince(_ unixMs: Int64) throws -> (words: Int, durationMs: Int) {
        unixMs == 0 ? totalSums : recentSums
    }
    func clear() throws {}
}

final class MetricsEngineTests: XCTestCase {
    func test_computesTotalAndWpm() throws {
        let s = MockStore()
        s.totalSums = (9313, 4_000_000)
        s.recentSums = (1280, 600_000) // 1280 words in 10 minutes → 128 wpm
        let engine = MetricsEngine(store: s)
        XCTAssertEqual(try engine.current(), Metrics(totalWords: 9313, wpm7d: 128))
    }

    func test_zeroDurationGivesZeroWpm() throws {
        let s = MockStore()
        let engine = MetricsEngine(store: s)
        XCTAssertEqual(try engine.current().wpm7d, 0)
    }

    func test_realStore_totalsNotCappedByHistoryPruning() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pt-test-\(UUID().uuidString).sqlite")
        let store = try HistoryStore(url: url)
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let n = HistoryStore.maxEntries * 2
        for i in 0..<n {
            _ = try store.append(.init(createdAt: nowMs - Int64(n - i), rawText: "", cleanedText: "",
                                       durationMs: 60_000, wordCount: 100, language: nil, inserted: true))
        }
        try store.clear() // clearing history must not reset metrics
        let m = try MetricsEngine(store: store).current(now: now)
        XCTAssertEqual(m, Metrics(totalWords: n * 100, wpm7d: 100))
    }
}
