import Foundation

public struct Metrics: Equatable, Sendable {
    /// Dictations since local midnight, and over the whole previous day.
    public let dictationsToday: Int
    public let dictationsYesterday: Int
    public let wpm7d: Int           // rounded to nearest int
    public init(dictationsToday: Int, dictationsYesterday: Int, wpm7d: Int) {
        self.dictationsToday = dictationsToday
        self.dictationsYesterday = dictationsYesterday
        self.wpm7d = wpm7d
    }
    public static let zero = Metrics(dictationsToday: 0, dictationsYesterday: 0, wpm7d: 0)
}

public protocol MetricsComputing {
    func current(now: Date) throws -> Metrics
}

public final class MetricsEngine: MetricsComputing {
    private let store: HistoryStoring
    private let resetAnchor: () -> Int64
    private let calendar: Calendar
    public init(store: HistoryStoring, resetAnchor: @escaping () -> Int64 = { 0 }, calendar: Calendar = .current) {
        self.store = store
        self.resetAnchor = resetAnchor
        self.calendar = calendar
    }

    public func current(now: Date = Date()) throws -> Metrics {
        let anchor = resetAnchor()
        let sevenDaysAgo = Int64((now.timeIntervalSince1970 - 7 * 86400) * 1000)
        let wpmAnchor = max(anchor, sevenDaysAgo)
        let sums = try store.sumsSince(wpmAnchor)
        let wpm: Int
        if sums.durationMs > 0 {
            wpm = Int((Double(sums.words) * 60_000.0 / Double(sums.durationMs)).rounded())
        } else {
            wpm = 0
        }

        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }
        // "Reset metrics" counts only what came after the anchor (exclusive, as in sumsSince).
        let floor = anchor + 1
        let today = try store.count(fromMs: max(floor, ms(todayStart)), toMs: Int64.max)
        let yesterday = try store.count(fromMs: max(floor, ms(yesterdayStart)), toMs: ms(todayStart))
        return Metrics(dictationsToday: today, dictationsYesterday: yesterday, wpm7d: wpm)
    }
}
