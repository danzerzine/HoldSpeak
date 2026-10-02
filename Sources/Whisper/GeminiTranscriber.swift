import Foundation

/// Cloud recognition through the Gemini API with the user's own key.
@MainActor
final class GeminiTranscriber {
    private let client = GeminiClient()

    func transcribe(_ trimmed: [Float], durationMs: Int) async -> TranscriptionResult {
        let prefs = PreferencesStore.shared
        guard let apiKey = prefs.geminiAPIKey, !apiKey.isEmpty else {
            pttLog("finalize: no Gemini API key")
            return .failed(.missingAPIKey)
        }
        // Gemini doesn't report the language, so in auto mode the terminology
        // language simply stays whatever it was.
        let language = prefs.primaryLanguage.whisperCode
        let terms = TerminologyStore.shared
            .entries(for: language ?? TerminologyStore.shared.activeLanguage)
            .map(\.canonical)
        let model = prefs.geminiModel
        let started = Date()
        do {
            let text = try await client.transcribe(
                wav: GeminiAPI.wav(trimmed),
                model: model,
                prompt: GeminiAPI.prompt(language: language, terms: terms),
                apiKey: apiKey
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            pttLog("finalize: gemini model=\(model.rawValue) text=\(logText(text)) dur=\(durationMs)ms request=\(ms)ms")
            if text.isEmpty { return .empty }
            return .text(text, language: language, durationMs: durationMs)
        } catch let failure as TranscriptionFailure {
            pttLog("finalize gemini failed: \(failure)")
            return .failed(failure)
        } catch {
            pttLog("finalize gemini error: \(error)")
            return .failed(.unreachable)
        }
    }
}
