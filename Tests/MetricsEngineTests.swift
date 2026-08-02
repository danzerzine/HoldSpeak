import XCTest
@testable import HoldSpeakCore

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
}
