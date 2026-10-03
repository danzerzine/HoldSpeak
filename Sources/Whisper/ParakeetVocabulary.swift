import Accelerate
import CoreML
import Foundation
import FluidAudio

/// FluidAudio vocabulary boosting for Parakeet. Parakeet often writes English terms
/// in Cyrillic ("пул реквист"); a small CTC keyword model (parakeet-ctc-110m, ~98 MB,
/// downloaded on first use) rescores words that sound like a dictionary term and puts
/// the term's Latin spelling in their place. Same steps as `fluidaudiocli transcribe
/// --custom-vocab` in batch mode.
@MainActor
final class ParakeetVocabulary {
    /// FluidAudio's size-aware default (0.60 for 100+ terms) let "конфиг" become
    /// "conflict"; 0.7 removed that swap without losing a term on the test clips.
    nonisolated static let minSimilarity: Float = 0.7
    private static let variant: CtcModelVariant = .ctc110m

    private var models: CtcModels?
    private var loadTask: Task<Void, Never>?
    private var built: (signature: Int, booster: Booster)?

    /// Starts loading (and on first use downloading) the keyword model in the background.
    func prepare() {
        guard models == nil, loadTask == nil else { return }
        loadTask = Task { @MainActor [weak self] in
            do {
                let loaded = try await CtcModels.downloadAndLoad(variant: Self.variant)
                self?.models = loaded
                pttLog("vocab: keyword model loaded")
            } catch {
                pttLog("vocab: keyword model failed to load: \(error)")
            }
            self?.loadTask = nil
        }
    }

    /// Waits for the keyword model; used by the file check, not by dictation.
    func waitUntilLoaded() async {
        prepare()
        await loadTask?.value
    }

    /// The booster for these terms, or nil while the keyword model is still loading
    /// or when no term has a Latin spelling.
    func booster(for entries: [TerminologyEntry]) async -> Booster? {
        guard let models else { prepare(); return nil }
        do {
            return try await context(for: entries, models: models)
        } catch {
            pttLog("vocab error: \(error)")
            return nil
        }
    }

    /// Everything one phrase needs, safe to use off the main actor so the keyword
    /// model can run while Parakeet decodes.
    struct Booster: Sendable {
        private static let noTerms = CustomVocabularyContext(terms: [])
        let vocabulary: CustomVocabularyContext
        let models: CtcModels
        let spotter: CtcKeywordSpotter
        let rescorer: VocabularyRescorer

        /// Runs the keyword model on the audio. Only its log-probs are used: an empty
        /// term list skips the spotter's own per-term search, the rescorer does that.
        func logProbs(_ samples: [Float]) async throws -> Spot {
            if let fast = try await fastLogProbs(samples) { return fast }
            let spot = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples, customVocabulary: Self.noTerms, minScore: nil)
            return Spot(logProbs: spot.logProbs, frameDuration: spot.frameDuration)
        }

        struct Spot: Sendable {
            let logProbs: [[Float]]
            let frameDuration: Double
        }

        /// The spotter's own path for one window, minus its per-element NSNumber copies.
        /// nil for inputs it does not cover (longer than one 15 s window, unexpected
        /// tensor types); the library path handles those.
        /// Temperature 1 and blank bias 0 are FluidAudio's defaults, so no scaling.
        func fastLogProbs(_ samples: [Float]) async throws -> Spot? {
            let window = ASRConstants.maxModelSamples
            let mel = models.melSpectrogram
            guard !samples.isEmpty, samples.count <= window,
                  let audioDesc = mel.modelDescription.inputDescriptionsByName["audio"]?.multiArrayConstraint
            else { return nil }

            let shape: [NSNumber] = audioDesc.shape.count == 2 ? [1, NSNumber(value: window)] : [NSNumber(value: window)]
            guard let audio = try Self.array(shape: shape, dataType: audioDesc.dataType, from: samples) else { return nil }
            var melInputs = ["audio": MLFeatureValue(multiArray: audio)]
            if mel.modelDescription.inputDescriptionsByName["audio_length"] != nil {
                melInputs["audio_length"] = MLFeatureValue(multiArray: try Self.int32(samples.count))
            }
            let melOut = try await mel.prediction(from: MLDictionaryFeatureProvider(dictionary: melInputs))
            guard let features = melOut.featureValue(for: "melspectrogram_features")?.multiArrayValue else { return nil }
            var melLength = melOut.featureValue(for: "mel_length")?.multiArrayValue?[0].intValue
                ?? features.shape.last?.intValue ?? 0
            if features.shape.count == 4 { melLength = features.shape[2].intValue }

            var inputs: [String: MLFeatureValue] = [
                "melspectrogram_features": MLFeatureValue(multiArray: features),
                "mel_length": MLFeatureValue(multiArray: try Self.int32(melLength)),
            ]
            if let flag = try? MLMultiArray(shape: [1, 1, 1, 1], dataType: .float16) {
                flag[0] = 1
                inputs["input_1"] = MLFeatureValue(multiArray: flag)
            }
            let encOut = try await models.encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
            guard let logits = encOut.featureValue(for: "ctc_head_raw_output")?.multiArrayValue
                    ?? encOut.featureValue(for: "ctc_head_output")?.multiArrayValue,
                  logits.shape.count == 3 || logits.shape.count == 4,
                  let data = Self.floats(logits)
            else { return nil }

            // [1, T, V] or [1, V, 1, T]
            let rank4 = logits.shape.count == 4
            let frames = logits.shape[rank4 ? 3 : 1].intValue
            let vocab = logits.shape[rank4 ? 1 : 2].intValue
            let tStride = logits.strides[rank4 ? 3 : 1].intValue
            let vStride = logits.strides[rank4 ? 1 : 2].intValue
            guard frames > 0, vocab > 0 else { return nil }
            let used = Int(ceil(Double(samples.count) / (Double(window) / Double(frames))))
            let keep = samples.count >= window ? frames : max(1, min(used, frames))

            var rows: [[Float]] = []
            rows.reserveCapacity(keep)
            var row = [Float](repeating: 0, count: vocab)
            for t in 0..<keep {
                var peak = -Float.infinity
                for v in 0..<vocab {
                    row[v] = data[t * tStride + v * vStride]
                    peak = max(peak, row[v])
                }
                var sum: Float = 0
                for v in 0..<vocab { sum += expf(row[v] - peak) }
                let norm = peak + logf(sum)
                rows.append(row.map { $0 - norm })
            }
            return Spot(logProbs: rows, frameDuration: Double(samples.count) / Double(keep) / 16_000)
        }

        /// Zero-padded model input of `dataType` (float32 or float16) holding `samples`.
        private static func array(shape: [NSNumber], dataType: MLMultiArrayDataType,
                                  from samples: [Float]) throws -> MLMultiArray? {
            guard dataType == .float32 || dataType == .float16 else { return nil }
            let array = try MLMultiArray(shape: shape, dataType: dataType)
            let width = dataType == .float16 ? 2 : 4
            memset(array.dataPointer, 0, array.count * width)
            samples.withUnsafeBufferPointer { src in
                if dataType == .float32 {
                    array.dataPointer.copyMemory(from: src.baseAddress!, byteCount: src.count * 4)
                } else {
                    var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src.baseAddress!), height: 1,
                                               width: vImagePixelCount(src.count), rowBytes: src.count * 4)
                    var target = vImage_Buffer(data: array.dataPointer, height: 1,
                                               width: vImagePixelCount(src.count), rowBytes: src.count * 2)
                    vImageConvert_PlanarFtoPlanar16F(&source, &target, 0)
                }
            }
            return array
        }

        /// The whole backing store (padding included, so `strides` index it) as Float.
        private static func floats(_ array: MLMultiArray) -> [Float]? {
            let count = array.strides[0].intValue * array.shape[0].intValue
            switch array.dataType {
            case .float32:
                return Array(UnsafeBufferPointer(start: array.dataPointer.assumingMemoryBound(to: Float.self), count: count))
            case .float16:
                var out = [Float](repeating: 0, count: count)
                out.withUnsafeMutableBytes { dst in
                    var source = vImage_Buffer(data: array.dataPointer, height: 1,
                                               width: vImagePixelCount(count), rowBytes: count * 2)
                    var target = vImage_Buffer(data: dst.baseAddress, height: 1,
                                               width: vImagePixelCount(count), rowBytes: count * 4)
                    vImageConvert_Planar16FtoPlanarF(&source, &target, 0)
                }
                return out
            default:
                return nil
            }
        }

        private static func int32(_ value: Int) throws -> MLMultiArray {
            let array = try MLMultiArray(shape: [1], dataType: .int32)
            array[0] = NSNumber(value: value)
            return array
        }

        /// `result.text` with dictionary terms swapped in.
        func apply(to result: ASRResult, spot: Spot) -> String {
            guard let timings = result.tokenTimings, !timings.isEmpty, !spot.logProbs.isEmpty
            else { return result.text }
            let sizeConfig = ContextBiasingConstants.rescorerConfig(forVocabSize: vocabulary.terms.count)
            let output = rescorer.ctcTokenRescore(
                transcript: result.text,
                tokenTimings: timings,
                logProbs: spot.logProbs,
                frameDuration: spot.frameDuration,
                cbw: sizeConfig.cbw,
                marginSeconds: ContextBiasingConstants.defaultMarginSeconds,
                minSimilarity: ParakeetVocabulary.minSimilarity)
            guard output.wasModified else { return result.text }
            let swaps = output.replacements.filter(\.shouldReplace)
                .map { "\($0.originalWord)→\($0.replacementWord ?? "")" }
            pttLog("vocab: \(swaps.joined(separator: ", "))")
            return ParakeetVocabulary.keepingFinalPunctuation(of: result.text, in: output.text)
        }
    }

    /// Rebuilt only when the term list changes (Terms tab edit or another language).
    private func context(for entries: [TerminologyEntry], models: CtcModels) async throws -> Booster? {
        let terms = entries.compactMap(Self.term(from:))
        var hasher = Hasher()
        for term in terms { hasher.combine(term.text); hasher.combine(term.aliases ?? []) }
        let signature = hasher.finalize()
        if let built, built.signature == signature { return built.booster }
        guard !terms.isEmpty else { built = nil; return nil }

        let directory = CtcModels.defaultCacheDirectory(for: Self.variant)
        let tokenizer = try await CtcTokenizer.load(from: directory)
        let tokenized = terms.compactMap { term -> CustomVocabularyTerm? in
            let ids = tokenizer.encode(term.text)
            guard !ids.isEmpty else { return nil }
            return CustomVocabularyTerm(text: term.text, aliases: term.aliases, ctcTokenIds: ids)
        }
        let vocabulary = CustomVocabularyContext(terms: tokenized)
        let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter, vocabulary: vocabulary, ctcModelDirectory: directory)
        let fresh = Booster(vocabulary: vocabulary, models: models, spotter: spotter, rescorer: rescorer)
        built = (signature, fresh)
        pttLog("vocab: \(tokenized.count) terms")
        return fresh
    }

    /// Only Latin-script canonicals are boosted: the booster's job is to undo Cyrillic
    /// spellings of English terms. Russian variants become aliases.
    private static func term(from entry: TerminologyEntry) -> CustomVocabularyTerm? {
        let text = entry.canonical.trimmingCharacters(in: .whitespaces)
        guard text.unicodeScalars.contains(where: { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }),
              !text.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) })
        else { return nil }
        let aliases = entry.variants.filter { !$0.isEmpty }
        return CustomVocabularyTerm(text: text, aliases: aliases.isEmpty ? nil : aliases)
    }

    /// The rescorer drops the sentence-final mark when the last word is swapped
    /// ("…на стейджинг." → "…на staging"); put it back.
    nonisolated static func keepingFinalPunctuation(of original: String, in boosted: String) -> String {
        guard let mark = original.last, ".!?…".contains(mark),
              let last = boosted.last, !".!?…".contains(last)
        else { return boosted }
        return boosted + String(mark)
    }
}
