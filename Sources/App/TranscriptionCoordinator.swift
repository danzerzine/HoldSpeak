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
    }

    private let engine: TranscriptionEngine
    private let store: HistoryStore

    init(engine: TranscriptionEngine, store: HistoryStore) {
        self.engine = engine
        self.store = store
    }

    func finishRecording() async -> Outcome {
        let startNs = DispatchTime.now().uptimeNanoseconds
        guard let result = await engine.finalize() else {
            pttLog("finalize returned nil (model not loaded or empty audio)")
            return .empty
        }
        let elapsedMs = (DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000
        pttLog("result raw: \"\(result.text)\" lang=\(result.language ?? "?") durMs=\(result.durationMs) elapsedMs=\(elapsedMs)")

        let prefs = PreferencesStore.shared
        let lang = result.language ?? prefs.primaryLanguage.whisperCode ?? TerminologyStore.shared.activeLanguage
        if prefs.primaryLanguage == .auto, let detected = result.language, !detected.isEmpty {
            TerminologyStore.shared.setActiveLanguage(detected)
        }
        let cleaned = TextCleaner.clean(
            result.text,
            terminology: TerminologyStore.shared.entries(for: lang),
            autoPunctuation: prefs.autoPunctuation,
            autoCapitalize: prefs.autoCapitalize
        )
        pttLog("cleaned: \"\(cleaned)\"")
        guard !cleaned.isEmpty else { return .empty }

        let insertion = TextInserter.insert(cleaned + " ")
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
