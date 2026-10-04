import Foundation
import Combine

public struct TerminologyEntry: Codable, Identifiable, Hashable {
    public var id: UUID
    public var canonical: String
    public var variants: [String]
    public var caseSensitive: Bool

    public init(id: UUID = UUID(), canonical: String, variants: [String], caseSensitive: Bool = false) {
        self.id = id
        self.canonical = canonical
        self.variants = variants
        self.caseSensitive = caseSensitive
    }
}

public extension Notification.Name {
    static let terminologyChanged = Notification.Name("HoldSpeak.terminologyChanged")
}

@MainActor
public final class TerminologyStore: ObservableObject {
    public enum MergeStrategy { case skipExisting, replaceAll }

    public static let shared = TerminologyStore()

    @Published public private(set) var entries: [TerminologyEntry] = []
    /// The language the Terms tab shows and edits.
    @Published public private(set) var activeLanguage: String
    /// Language of the last dictation: picks the dictionary at runtime. Kept apart
    /// from `activeLanguage` so browsing another dictionary doesn't change dictation.
    public private(set) var dictationLanguage: String

    private var cache: [String: [TerminologyEntry]] = [:]

    private let directory: URL
    private let bundle: Bundle
    private let defaultsBundlePrefix: String

    public init(directory: URL = TerminologyStore.defaultDirectory(),
                bundle: Bundle = .main,
                defaultsBundlePrefix: String = "terminology-default",
                legacyFlatFile: URL? = TerminologyStore.legacyFlatFile(),
                initialLanguage: String = PrimaryLanguage.systemDefault.whisperCode ?? "en") {
        self.directory = directory
        self.bundle = bundle
        self.defaultsBundlePrefix = defaultsBundlePrefix
        self.activeLanguage = initialLanguage
        self.dictationLanguage = initialLanguage
        bootstrap(legacyFlatFile: legacyFlatFile)
        loadActive()
    }

    public nonisolated static func defaultDirectory() -> URL {
        AppPaths.support.appendingPathComponent("terminology")
    }

    public nonisolated static func legacyFlatFile() -> URL {
        AppPaths.support.appendingPathComponent("terminology.json")
    }

    // MARK: - Bootstrap

    private func bootstrap(legacyFlatFile: URL?) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let legacy = legacyFlatFile, fm.fileExists(atPath: legacy.path) {
            let target = fileURL(for: "ru")
            if !fm.fileExists(atPath: target.path) {
                try? fm.moveItem(at: legacy, to: target)
                pttLog("TerminologyStore: migrated legacy terminology.json → terminology/ru.json")
            }
        }
    }

    private func fileURL(for language: String) -> URL {
        directory.appendingPathComponent("\(language).json")
    }

    private func seedURL(for language: String) -> URL? {
        bundle.url(forResource: "\(defaultsBundlePrefix)-\(language)", withExtension: "json")
    }

    public func hasSeed(for language: String) -> Bool { seedURL(for: language) != nil }

    // MARK: - Active language

    public func setActiveLanguage(_ code: String) {
        guard !code.isEmpty, code != activeLanguage else { return }
        activeLanguage = code
        loadActive()
    }

    public func setDictationLanguage(_ code: String) {
        guard !code.isEmpty else { return }
        dictationLanguage = code
    }

    public func entries(for language: String) -> [TerminologyEntry] {
        if let cached = cache[language] { return cached }
        let loaded = loadFromDisk(language) ?? seedEntries(for: language) ?? []
        cache[language] = loaded
        return loaded
    }

    private func loadActive() {
        let loaded: [TerminologyEntry]
        if let disk = loadFromDisk(activeLanguage) {
            loaded = disk
        } else if let seed = seedEntries(for: activeLanguage) {
            loaded = seed
            writeToDisk(seed, language: activeLanguage)
        } else {
            loaded = []
        }
        cache[activeLanguage] = loaded
        entries = loaded
    }

    private func loadFromDisk(_ language: String) -> [TerminologyEntry]? {
        let url = fileURL(for: language)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TerminologyEntry].self, from: data)
        else { return nil }
        return decoded
    }

    private func seedEntries(for language: String) -> [TerminologyEntry]? {
        guard let url = seedURL(for: language),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TerminologyEntry].self, from: data)
        else { return nil }
        return decoded
    }

    private func writeToDisk(_ entries: [TerminologyEntry], language: String) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL(for: language), options: .atomic)
        } catch {
            pttLog("TerminologyStore: save error (\(language)): \(error)")
        }
    }

    // MARK: - Mutations on active set

    private func persistActive() {
        cache[activeLanguage] = entries
        writeToDisk(entries, language: activeLanguage)
        NotificationCenter.default.post(name: .terminologyChanged, object: nil)
    }

    public func add(_ entry: TerminologyEntry) {
        entries.append(entry)
        persistActive()
    }

    public func update(_ entry: TerminologyEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        persistActive()
    }

    public enum CorrectionResult: Equatable {
        case addedVariant(canonical: String)
        case newTerm
        case alreadyThere
        case invalid
    }

    /// "Transcribed as `wrong`, should be `right`". Joins the entry whose
    /// canonical matches `right` (ignoring case) or starts a new one, and drops
    /// `wrong` from any other entry so one spelling maps to one term.
    @discardableResult
    public func addCorrection(wrong: String, right: String) -> CorrectionResult {
        let wrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wrong.isEmpty, !right.isEmpty, wrong != right else { return .invalid }
        let same: (String, String) -> Bool = { $0.caseInsensitiveCompare($1) == .orderedSame }

        let target = entries.firstIndex { $0.canonical == right }
            ?? entries.firstIndex { same($0.canonical, right) }
        if let t = target, entries[t].variants.contains(where: { same($0, wrong) }) {
            return .alreadyThere
        }
        for i in entries.indices where i != target {
            entries[i].variants.removeAll { same($0, wrong) }
        }
        let result: CorrectionResult
        if let t = target {
            entries[t].variants.append(wrong)
            result = .addedVariant(canonical: entries[t].canonical)
        } else {
            entries.insert(TerminologyEntry(canonical: right, variants: [wrong]), at: 0)
            result = .newTerm
        }
        persistActive()
        return result
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persistActive()
    }

    /// Puts back an entry removed by mistake, at its old position when possible.
    public func restore(_ entry: TerminologyEntry, at index: Int) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.insert(entry, at: min(max(index, 0), entries.count))
        persistActive()
    }

    /// Adds entries whose canonical form isn't in the list yet.
    public func addMissing(_ newEntries: [TerminologyEntry]) {
        let existing = Set(entries.map { $0.canonical.lowercased() })
        entries.append(contentsOf: newEntries.filter { !existing.contains($0.canonical.lowercased()) })
        persistActive()
    }

    public func replaceAll(_ newEntries: [TerminologyEntry]) {
        entries = newEntries
        persistActive()
    }

    public func loadDefaults(mergeStrategy: MergeStrategy) {
        guard let defaults = seedEntries(for: activeLanguage) else {
            pttLog("TerminologyStore: no seed for \(activeLanguage)")
            return
        }
        switch mergeStrategy {
        case .replaceAll:
            entries = defaults
        case .skipExisting:
            addMissing(defaults)
            return
        }
        persistActive()
    }
}
