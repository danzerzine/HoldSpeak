import AppKit

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
        /// No text field and the history write failed: the text went to the clipboard.
        case noFocusCopied
        /// The engine couldn't transcribe (no model, bad key, quota, network).
        case failed(TranscriptionFailure)
    }

    private let engine: TranscriptionEngine
    private let store: HistoryStore
    /// Tail of the FIFO: each finish waits for the previous one so two transcriptions
    /// never share the WhisperKit instance and text is inserted in dictation order.
    private var lastFinish: Task<Outcome, Never>?

    init(engine: TranscriptionEngine, store: HistoryStore) {
        self.engine = engine
        self.store = store
    }

    func finishRecording(samples: [Float]) async -> Outcome {
        let previous = lastFinish
        let task = Task { [weak self] () -> Outcome in
            _ = await previous?.value
            guard let self else { return .empty }
            return await self.process(samples)
        }
        lastFinish = task
        return await task.value
    }

    private func process(_ samples: [Float]) async -> Outcome {
        let startNs = DispatchTime.now().uptimeNanoseconds
        let result: (text: String, language: String?, durationMs: Int)
        switch await engine.finalize(samples: samples) {
        case .text(let text, let language, let durationMs):
            result = (text, language, durationMs)
        case .empty:
            return .empty
        case .failed(let failure):
            return .failed(failure)
        }
        let elapsedMs = (DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000
        pttLog("result raw: \(logText(result.text)) lang=\(result.language ?? "?") durMs=\(result.durationMs) elapsedMs=\(elapsedMs)")

        let prefs = PreferencesStore.shared
        let lang = result.language ?? prefs.primaryLanguage.whisperCode ?? TerminologyStore.shared.dictationLanguage
        if prefs.primaryLanguage == .auto, let detected = result.language, !detected.isEmpty {
            TerminologyStore.shared.setDictationLanguage(detected)
        }
        let cleaned = TextCleaner.clean(
            result.text,
            terminology: TerminologyStore.shared.entries(for: lang),
            autoPunctuation: prefs.autoPunctuation,
            autoCapitalize: prefs.autoCapitalize,
            // The blacklist targets Whisper's decoder inventing subtitle boilerplate on
            // silence. Parakeet and Gemini don't, so there "Спасибо" is real speech.
            dropHallucinations: prefs.engine == .whisper && !prefs.modelID.isParakeet
        )
        pttLog("cleaned: \(logText(cleaned))")
        guard !cleaned.isEmpty else { return .empty }

        let insertion = TextInserter.insert(cleaned + " ")
        pttLog("insertion: \(insertion)")
        // A password field gets nothing: not typed, and not kept in history (audit 2.10).
        if insertion == .skippedSecureField { return .skippedSecureField }
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
        do {
            _ = try store.append(record)
        } catch {
            pttLog("History write failed: \(error)")
            // With no text field the history row is the only copy of the dictation.
            if insertion == .noFocus {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cleaned, forType: .string)
                return .noFocusCopied
            }
        }

        switch insertion {
        case .inserted:          return .inserted
        case .skippedSecureField: return .skippedSecureField
        case .noFocus:           return .noFocus
        }
    }
}
