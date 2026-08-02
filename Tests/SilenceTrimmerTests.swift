import XCTest
@testable import HoldSpeakCore

final class SilenceTrimmerTests: XCTestCase {
    private let vad = SilenceTrimmer()

    /// 16 kHz samples: `ms` milliseconds of a 440 Hz tone at the given amplitude.
    private func tone(ms: Int, amplitude: Float = 0.3) -> [Float] {
        let count = ms * 16
        return (0..<count).map { amplitude * sin(2 * .pi * 440 * Float($0) / 16_000) }
    }

    private func silence(ms: Int) -> [Float] {
        [Float](repeating: 0, count: ms * 16)
    }

    func test_pureSilenceReturnsNil() {
        XCTAssertNil(vad.trimSilence(silence(ms: 2000)))
    }

    func test_bufferShorterThanOneWindowReturnsNil() {
        XCTAssertNil(vad.trimSilence(tone(ms: 20)))
    }

    func test_blipShorterThanMinDurationReturnsNil() {
        var d = SilenceTrimmer()
        d.paddingMs = 0
        XCTAssertNil(d.trimSilence(silence(ms: 500) + tone(ms: 60) + silence(ms: 500)))
    }

    func test_trimsSurroundingSilenceKeepingPadding() {
        let input = silence(ms: 1000) + tone(ms: 600) + silence(ms: 1000)
        let out = vad.trimSilence(input)
        XCTAssertNotNil(out)
        let outMs = out!.count / 16
        // Expect roughly speech + 2×250ms padding, never the full 2.6s input.
        XCTAssertGreaterThanOrEqual(outMs, 600)
        XCTAssertLessThanOrEqual(outMs, 600 + 2 * 250 + 60)
    }

    func test_speechWithNoSurroundingSilencePassesThrough() {
        let input = tone(ms: 800)
        let out = vad.trimSilence(input)
        XCTAssertNotNil(out)
        XCTAssertEqual(out!.count / 16, 800, accuracy: 40)
    }

    func test_quietSpeechAboveFloorIsKept() {
        let input = silence(ms: 300) + tone(ms: 500, amplitude: 0.005) + silence(ms: 300)
        XCTAssertNotNil(vad.trimSilence(input))
    }

    private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(a - b), accuracy, "\(a) != \(b) ± \(accuracy)",
                                 file: file, line: line)
    }
}
