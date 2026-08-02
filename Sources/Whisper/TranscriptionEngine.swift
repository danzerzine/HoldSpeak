import AVFoundation
import WhisperKit

@MainActor
public final class TranscriptionEngine {
    private var kit: WhisperKit?
    private var currentModelID: WhisperModelID?
    private var accumulated: [Float] = []
    private var promptTokens: [Int]?
    private var terminologyObserver: NSObjectProtocol?
    private var activeLanguageObserver: NSObjectProtocol?

    private let baseInitialPrompt =
        "Смешанная русско-английская речь. Сохраняй английские термины в оригинале: meeting, deadline, pull request."

    // Tuning constants (exposed as `private static` for easy adjustment).
    private static let codeSwitchDeltaThreshold: Float = 0.25
    private static let codeSwitchMinProb: Float = 0.15
    private static let promptTokenBudget: Int = 60

    private let vad = SilenceTrimmer()

    /// When true, the base + terminology prompt is passed to Whisper's decoder as
    /// `promptTokens`. This biases the model toward those terms but also disables
    /// WhisperKit's prefill KV-cache path (see TextDecoder.swift in WhisperKit), which
    /// in our tests caused intermittent empty/corrupted results. Terminology replacement
    /// still runs unconditionally as post-processing in TextCleaner.
    private static let usePromptBiasing = false

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

    public init() {
        terminologyObserver = NotificationCenter.default.addObserver(
            forName: .terminologyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildPromptTokens()
            }
        }
        activeLanguageObserver = NotificationCenter.default.addObserver(
            forName: .terminologyActiveLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildPromptTokens()
            }
        }
    }

    deinit {
        if let obs = terminologyObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = activeLanguageObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    public func preload(model: WhisperModelID) async throws {
        if currentModelID == model, kit != nil { return }
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
        rebuildPromptTokens()
    }

    private func rebuildPromptTokens() {
        guard kit != nil else { return }
        let hint = TerminologyStore.shared.promptHint(for: TerminologyStore.shared.activeLanguage)
        let fullPrompt = hint.isEmpty
            ? baseInitialPrompt
            : baseInitialPrompt + " Термины: " + hint + "."
        promptTokens = tokenizePrompt(fullPrompt, budget: Self.promptTokenBudget)
    }

    private func tokenizePrompt(_ prompt: String, budget: Int) -> [Int]? {
        guard let tokenizer = kit?.tokenizer else { return nil }
        let encoded = tokenizer.encode(text: " " + prompt)
        if encoded.isEmpty { return nil }
        if encoded.count <= budget { return encoded }
        pttLog("TranscriptionEngine: prompt truncated \(encoded.count) → \(budget) tokens")
        return Array(encoded.prefix(budget))
    }

    public func beginStream() {
        accumulated.removeAll(keepingCapacity: true)
    }

    public func feed(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        accumulated.append(contentsOf: UnsafeBufferPointer(start: ch, count: count))
    }

    public func finalize() async -> (text: String, language: String?, durationMs: Int)? {
        guard let kit else { pttLog("finalize: kit is nil"); return nil }
        guard !accumulated.isEmpty else { pttLog("finalize: accumulated empty (no audio captured)"); return nil }
        let rawMs = Int(Double(accumulated.count) / 16.0)
        guard let trimmed = vad.trimSilence(accumulated) else {
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
            pttLog("finalize: text=\"\(text)\" lang=\(lang ?? "?") override=\(override ?? "nil") dur=\(durationMs)ms")
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
        guard preferred.count >= 2 else {
            return preferred.first
        }
        let detection = try await kit.detectLangauge(audioArray: samples)
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
                return nil      // let Whisper switch languages per-segment
            }
        } else {
            pttLog("finalize detect: top1=\(top1.code):\(top1.prob) (only candidate in preferred)")
        }
        return top1.code
    }

    private func makeOptions(override: String? = nil) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: override ?? PreferencesStore.shared.primaryLanguage.whisperCode,
            temperature: 0.0,
            temperatureIncrementOnFallback: 0.2,
            temperatureFallbackCount: 2,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: Self.usePromptBiasing ? promptTokens : nil,
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
