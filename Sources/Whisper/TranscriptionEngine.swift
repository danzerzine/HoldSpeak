import AVFoundation
import WhisperKit

@MainActor
public final class TranscriptionEngine {
    private var kit: WhisperKit?
    private var currentModelID: WhisperModelID?
    /// Most recent model asked for; a queued load that has been superseded is skipped.
    private var requestedModelID: WhisperModelID?
    /// Tail of the load queue — each preload waits for the previous one so two
    /// WhisperKit instances are never built concurrently.
    private var loadTask: Task<Void, Error>?
    private var accumulated: [Float] = []

    // Tuning constants (exposed as `private static` for easy adjustment).
    private static let codeSwitchDeltaThreshold: Float = 0.25
    private static let codeSwitchMinProb: Float = 0.15

    private let vad = SilenceTrimmer()

    private static let whisperCodes: Set<String> = [
        "en","zh","de","es","ru","ko","fr","ja","pt","tr","pl","ca","nl","ar","sv","it","id","hi","fi","vi","he","uk",
        "el","ms","cs","ro","da","hu","ta","no","th","ur","hr","bg","lt","la","mi","ml","cy","sk","te","fa","lv","bn",
        "sr","az","sl","kn","et","mk","br","eu","is","hy","ne","mn","bs","kk","sq","sw","gl","mr","pa","si","km",
        "sn","yo","so","af","oc","ka","be","tg","sd","gu","am","yi","lo","uz","fo","ht","ps","tk","nn","mt","sa",
        "lb","my","bo","tl","mg","as","tt","haw","ln","ha","ba","jw","su"
    ]

    private static func userPreferredLanguages() -> [String] {
        let codes = Locale.preferredLanguages.compactMap { tag -> String? in
            let two = String(tag.prefix(2)).lowercased()
            return whisperCodes.contains(two) ? two : nil
        }
        return codes.isEmpty ? ["en"] : Array(NSOrderedSet(array: codes)) as? [String] ?? ["en"]
    }

    public init() {}

    public func preload(model: WhisperModelID) async throws {
        requestedModelID = model
        let previous = loadTask
        let task = Task { @MainActor [weak self] in
            _ = await previous?.result
            guard let self, self.requestedModelID == model else { return }
            if self.currentModelID == model, self.kit != nil { return }
            try await self.load(model: model)
        }
        loadTask = task
        try await task.value
    }

    private func load(model: WhisperModelID) async throws {
        let url: URL
        if let local = ModelManager.shared.locateModel(model) {
            url = local
        } else {
            url = try await ModelManager.shared.download(model) { _ in }
        }
        let config = WhisperKitConfig(modelFolder: url.path,
                                      verbose: false,
                                      logLevel: .error,
                                      download: false)
        kit = try await WhisperKit(config)
        currentModelID = model
    }

    /// Hands over everything fed since the last call and starts a fresh buffer.
    /// Call synchronously from the recorder's stop completion: every chunk of the
    /// finished recording has been fed by then, and none of the next one yet.
    public func takeSamples() -> [Float] {
        defer { accumulated = [] }
        return accumulated
    }

    public func feed(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        accumulated.append(contentsOf: UnsafeBufferPointer(start: ch, count: count))
    }

    public func finalize(samples: [Float]) async -> (text: String, language: String?, durationMs: Int)? {
        guard let kit else { pttLog("finalize: kit is nil"); return nil }
        guard !samples.isEmpty else { pttLog("finalize: samples empty (no audio captured)"); return nil }
        let rawMs = Int(Double(samples.count) / 16.0)
        guard let trimmed = vad.trimSilence(samples) else {
            pttLog("finalize: VAD dropped buffer (raw=\(rawMs)ms)")
            return nil
        }
        let durationMs = Int(Double(trimmed.count) / 16.0)
        pttLog("finalize: VAD raw=\(rawMs)ms → trimmed=\(durationMs)ms")
        let isAuto = PreferencesStore.shared.primaryLanguage == .auto
        let preferred = Self.userPreferredLanguages()
        let padded = padShortSegment(trimmed)
        do {
            let override = try await chooseLanguage(kit: kit, samples: padded, isAuto: isAuto, preferred: preferred)
            let results = try await kit.transcribe(audioArray: padded, decodeOptions: makeOptions(override: override))
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let lang = results.first?.language
            pttLog("finalize: text=\(logText(text)) lang=\(lang ?? "?") override=\(override ?? "nil") dur=\(durationMs)ms")
            if text.isEmpty { return nil }
            return (text, lang, durationMs)
        } catch {
            pttLog("finalize error: \(error)")
            return nil
        }
    }

    private func chooseLanguage(kit: WhisperKit, samples: [Float], isAuto: Bool, preferred: [String]) async throws -> String? {
        if !isAuto {
            return PreferencesStore.shared.primaryLanguage.whisperCode
        }
        let detection = try await kit.detectLangauge(audioArray: samples)
        guard preferred.count >= 2 else {
            // Nothing to arbitrate between — trust Whisper's own pick. Returning nil
            // here would not detect: with prefill on, WhisperKit falls back to "en".
            pttLog("finalize detect: \(detection.language) (fewer than 2 preferred languages)")
            return detection.language
        }
        let ranked = preferred
            .compactMap { code -> (code: String, prob: Float)? in
                guard let p = detection.langProbs[code] else { return nil }
                return (code, p)
            }
            .sorted { $0.prob > $1.prob }
        guard let top1 = ranked.first else { return preferred[0] }
        if ranked.count >= 2 {
            let top2 = ranked[1]
            let delta = top1.prob - top2.prob
            pttLog("finalize detect: top1=\(top1.code):\(top1.prob) top2=\(top2.code):\(top2.prob) delta=\(delta)")
            if delta < Self.codeSwitchDeltaThreshold && top2.prob > Self.codeSwitchMinProb {
                return nil      // too close to call: let Whisper detect during decoding (see makeOptions)
            }
        } else {
            pttLog("finalize detect: top1=\(top1.code):\(top1.prob) (only candidate in preferred)")
        }
        return top1.code
    }

    private func makeOptions(override: String? = nil) -> DecodingOptions {
        let language = override ?? PreferencesStore.shared.primaryLanguage.whisperCode
        return DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            // With prefill on, WhisperKit's detectLanguage defaults to false and a nil
            // language decodes as "en". Enable detection only when no language is set;
            // WhisperKit ignores it whenever `language` is non-nil.
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            // No promptTokens: prompt biasing disables WhisperKit's prefill KV-cache
            // path, which caused intermittent empty/corrupted results. Terminology is
            // applied after transcription by TextCleaner instead.
            suppressBlank: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.5,
            noSpeechThreshold: nil
        )
    }

    /// Whisper is trained on 30s windows; sub-second segments can be mis-classified as
    /// silence. Pad short inputs with leading/trailing silence to at least 1s total.
    private func padShortSegment(_ samples: [Float]) -> [Float] {
        let minSamples = 32_000
        guard samples.count < minSamples else { return samples }
        let deficit = minSamples - samples.count
        let lead = deficit / 2
        let trail = deficit - lead
        return Array(repeating: 0, count: lead) + samples + Array(repeating: 0, count: trail)
    }
}
