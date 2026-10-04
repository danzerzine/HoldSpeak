import Foundation

/// Where the app keeps its files, and the one-time move from the names it had
/// before it became Speak! (HoldSpeak, push-to-talk before that).
public enum AppPaths {
    /// Bundle id of the HoldSpeak builds; its preferences domain holds the old settings.
    public static let previousBundleID = "com.timmal.push-to-talk"
    /// Set in the new domain once the old settings were copied (or found empty).
    static let migratedKey = "migratedFromHoldSpeak"

    /// ~/Library/Application Support/Speak: models, history, dictionaries.
    public static var support: URL { supportBase().appendingPathComponent("Speak") }

    /// ~/Library/Logs/Speak.log
    public static var logFile: String { ("~/Library/Logs/Speak.log" as NSString).expandingTildeInPath }

    public static func supportBase() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Moves Application Support/HoldSpeak (or the older push-to-talk) to Speak
    /// unless Speak already exists. Returns the folder it moved, nil if none.
    @discardableResult
    public static func migrateSupportDirectory(base: URL = supportBase(),
                                               fm: FileManager = .default) throws -> String? {
        let target = base.appendingPathComponent("Speak")
        guard !fm.fileExists(atPath: target.path) else { return nil }
        for name in ["HoldSpeak", "push-to-talk"] {
            let legacy = base.appendingPathComponent(name)
            guard fm.fileExists(atPath: legacy.path) else { continue }
            try fm.moveItem(at: legacy, to: target)
            return name
        }
        return nil
    }

    /// Settings saved by the HoldSpeak builds, read straight from their domain.
    public static func previousDefaults() -> [String: Any] {
        let domain = previousBundleID as CFString
        guard let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
              let values = CFPreferencesCopyMultiple(keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                as? [String: Any] else { return [:] }
        return values
    }

    /// Copies the old settings into `defaults` once; keys already set there win.
    /// Returns true on the run that copied something.
    @discardableResult
    public static func migrateDefaults(from old: [String: Any], into defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: migratedKey) else { return false }
        defaults.set(true, forKey: migratedKey)
        guard !old.isEmpty else { return false }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        return true
    }
}
