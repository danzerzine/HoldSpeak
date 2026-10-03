import AVFoundation

public enum TranscriptionResult {
    case text(String, language: String?, durationMs: Int)
    /// Silence or nothing recognisable — nothing to tell the user.
    case empty
    case failed(TranscriptionFailure)
}

/// Collects the recording's samples and hands them to the engine picked in
/// Preferences (read on every finalize, so switching takes effect immediately).
@MainActor
public final class TranscriptionEngine {
    private let whisper = WhisperTranscriber()
    private let gemini = GeminiTranscriber()
    private var accumulated: [Float] = []
    private let vad = SilenceTrimmer()

    public init() {}

    public func preload(model: WhisperModelID) async throws {
        try await whisper.preload(model: model)
    }

    public func unloadWhisper() {
        whisper.unload()
    }

    /// Hands over everything fed since the last call and starts a fresh buffer.
    /// Call synchronously from the recorder's stop completion: every chunk of the
    /// finished recording has been fed by then, and none of the next one yet.
    public func takeSamples() -> [Float] {
        #if DEBUG
        testCursor = 0
        #endif
        lastPartial = (0, nil)
        defer { accumulated = [] }
        return accumulated
    }

    /// The recording so far, left in place for `takeSamples`.
    public func peekSamples() -> [Float] { accumulated }

    public var canTranscribeLive: Bool {
        PreferencesStore.shared.engine == .whisper && whisper.canTranscribeLive
    }

    /// Trimmed like the final pass: silence added during a pause trims away, so the
    /// partial stays put instead of wobbling, and it matches what the final will hear.
    /// No new speech since the last call returns the last text without re-running.
    public func partial(samples: [Float]) async -> String? {
        guard canTranscribeLive, let trimmed = vad.trimSilence(samples) else { return nil }
        if trimmed.count == lastPartial.count { return lastPartial.text }
        let text = await whisper.partial(trimmed)
        lastPartial = (trimmed.count, text)
        return text
    }
    private var lastPartial: (count: Int, text: String?) = (0, nil)

    public func feed(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        #if DEBUG
        if let test = Self.testInput {
            let end = min(testCursor + count, test.count)
            accumulated.append(contentsOf: test[testCursor..<end])
            accumulated.append(contentsOf: repeatElement(0, count: count - (end - testCursor)))
            testCursor = end
            return
        }
        #endif
        accumulated.append(contentsOf: UnsafeBufferPointer(start: ch, count: count))
    }

    #if DEBUG
    /// Debug builds: HOLDSPEAK_TEST_WAV (comma-separated 16 kHz mono files) replaces
    /// the microphone, paced by its buffers, so dictation can be tested end to end.
    private static let testInput: [Float]? = {
        guard let paths = ProcessInfo.processInfo.environment["HOLDSPEAK_TEST_WAV"] else { return nil }
        var out: [Float] = []
        for path in paths.split(separator: ",") {
            guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: String(path)),
                                              commonFormat: .pcmFormatFloat32, interleaved: false),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil,
                  let ch = buf.floatChannelData?[0] else { continue }
            out.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
        }
        pttLog("test input: \(out.count / 16) ms from HOLDSPEAK_TEST_WAV")
        return out
    }()
    private var testCursor = 0
    #endif

    public func finalize(samples: [Float]) async -> TranscriptionResult {
        guard !samples.isEmpty else { pttLog("finalize: samples empty (no audio captured)"); return .empty }
        let rawMs = Int(Double(samples.count) / 16.0)
        guard let trimmed = vad.trimSilence(samples) else {
            pttLog("finalize: VAD dropped buffer (raw=\(rawMs)ms)")
            return .empty
        }
        let durationMs = Int(Double(trimmed.count) / 16.0)
        pttLog("finalize: VAD raw=\(rawMs)ms → trimmed=\(durationMs)ms")
        switch PreferencesStore.shared.engine {
        case .whisper: return await whisper.transcribe(trimmed, durationMs: durationMs)
        case .gemini:  return await gemini.transcribe(trimmed, durationMs: durationMs)
        }
    }
}
