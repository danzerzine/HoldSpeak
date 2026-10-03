import Foundation

/// Runs the post-recording pipeline: finalize → clean → insert → persist.
/// UI reactions (notifications, popover refresh) stay in AppDelegate.
@MainActor
final class TranscriptionCoordinator {
    enum Outcome {
        /// Nothing usable was transcribed; nothing inserted or persisted.
        case empty
        case inserted
        case skippedSecureField
        case noFocus
        /// The engine couldn't transcribe (no model, bad key, quota, network).
        case failed(TranscriptionFailure)
    }

    private let engine: TranscriptionEngine
    private let store: HistoryStore
    /// Tail of the FIFO: each finish waits for the previous one so two transcriptions
    /// never share the WhisperKit instance and text is inserted in dictation order.
    private var lastFinish: Task<Outcome, Never>?
    private var pending = 0
    /// A previous recording is still being transcribed or inserted.
    var isBusy: Bool { pending > 0 }

    init(engine: TranscriptionEngine, store: HistoryStore) {
        self.engine = engine
        self.store = store
    }

    /// `live` typed a running transcript during the hold; the final text corrects it.
    func finishRecording(samples: [Float], live: LiveTyper? = nil) async -> Outcome {
        let previous = lastFinish
        pending += 1
        let task = Task { [weak self] () -> Outcome in
            await live?.stop()
            _ = await previous?.value
            guard let self else { return .empty }
            defer { self.pending -= 1 }
            return await self.process(samples, live: live)
        }
        lastFinish = task
        return await task.value
    }

    /// Partial transcripts typed during the hold: no closing period yet, the final adds it.
    func cleanPartial(_ raw: String) -> String {
        let prefs = PreferencesStore.shared
        return TextCleaner.clean(
            raw,
            terminology: TerminologyStore.shared.entries(for: terminologyLanguage(nil)),
            autoPunctuation: false,
            autoCapitalize: prefs.autoCapitalize,
            dropHallucinations: prefs.engine == .whisper
        )
    }

    private func terminologyLanguage(_ detected: String?) -> String {
        detected ?? PreferencesStore.shared.primaryLanguage.whisperCode ?? TerminologyStore.shared.activeLanguage
    }

    private func process(_ samples: [Float], live: LiveTyper?) async -> Outcome {
        let startNs = DispatchTime.now().uptimeNanoseconds
        let result: (text: String, language: String?, durationMs: Int)
        switch await engine.finalize(samples: samples) {
        case .text(let text, let language, let durationMs):
            result = (text, language, durationMs)
        case .empty:
            _ = live?.finish("")
            return .empty
        case .failed(let failure):
            _ = live?.finish("")
            return .failed(failure)
        }
        let elapsedMs = (DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000
        pttLog("result raw: \(logText(result.text)) lang=\(result.language ?? "?") durMs=\(result.durationMs) elapsedMs=\(elapsedMs)")

        let prefs = PreferencesStore.shared
        let lang = terminologyLanguage(result.language)
        if prefs.primaryLanguage == .auto, let detected = result.language, !detected.isEmpty {
            TerminologyStore.shared.setActiveLanguage(detected)
        }
        let cleaned = TextCleaner.clean(
            result.text,
            terminology: TerminologyStore.shared.entries(for: lang),
            autoPunctuation: prefs.autoPunctuation,
            autoCapitalize: prefs.autoCapitalize,
            dropHallucinations: prefs.engine == .whisper
        )
        pttLog("cleaned: \(logText(cleaned))")
        guard !cleaned.isEmpty else { _ = live?.finish(""); return .empty }

        let insertion = live?.finish(cleaned + " ") ?? TextInserter.insert(cleaned + " ")
        pttLog("insertion: \(insertion)")
        let record = TranscriptionRecord(
            id: nil,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            rawText: result.text,
            cleanedText: cleaned,
            durationMs: result.durationMs,
            wordCount: cleaned.split(whereSeparator: { $0.isWhitespace }).count,
            language: result.language,
            inserted: insertion == .inserted
        )
        _ = try? store.append(record)

        switch insertion {
        case .inserted:          return .inserted
        case .skippedSecureField: return .skippedSecureField
        case .noFocus:           return .noFocus
        }
    }
}
