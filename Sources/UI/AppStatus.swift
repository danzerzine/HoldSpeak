import AppKit
import Combine

/// What the app is doing right now, in one place: the menu bar icon, the HUD and
/// the popover all read it. AppDelegate writes the dictation phase and model
/// loading; permissions refresh themselves.
@MainActor
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    enum Phase: Equatable { case idle, listening, transcribing }

    /// What the menu bar icon shows, most urgent first.
    enum IconState: Equatable { case ready, listening, transcribing, loading, error, attention }

    @Published var phase: Phase = .idle
    /// The local model is loading into memory (first start, after an update or a switch).
    @Published var modelLoading = false
    /// The last dictation failed; cleared by the next success or by opening the popover.
    @Published var lastDictationFailed = false
    @Published private(set) var permissions = PermissionsManager.shared.current()
    /// Bumped on every successful insert: the icon "pops" once.
    @Published private(set) var insertPulse = 0

    private var timer: Timer?

    private init() {
        // macOS has no callback for privacy changes: check when the app becomes
        // active and, while something is missing, every 2 s.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        scheduleRefresh()
    }

    var needsSetup: Bool { !permissions.microphone || !permissions.accessibility }

    var iconState: IconState {
        switch phase {
        case .listening:    return .listening
        case .transcribing: return .transcribing
        case .idle: break
        }
        if modelLoading { return .loading }
        if lastDictationFailed { return .error }
        if needsSetup || !PreferencesStore.shared.engineChosen { return .attention }
        return .ready
    }

    /// Spoken name of the state, for VoiceOver.
    var iconDescription: String {
        switch iconState {
        case .ready:        return "Speak!, ready"
        case .listening:    return "Speak!, listening"
        case .transcribing: return "Speak!, transcribing"
        case .loading:      return "Speak!, loading the speech model"
        case .error:        return "Speak!, the last dictation failed"
        case .attention:    return "Speak!, needs setup"
        }
    }

    func inserted() {
        lastDictationFailed = false
        insertPulse += 1
    }

    func refreshPermissions() {
        let now = PermissionsManager.shared.current()
        if now != permissions { permissions = now }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        let missing = !permissions.microphone || !permissions.accessibility || !permissions.inputMonitoring
        if missing, timer == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !missing {
            timer?.invalidate()
            timer = nil
        }
    }
}

/// Human names for the engine and model, shared by the popover, HUD and Settings.
enum EngineText {
    static func modelName(_ prefs: PreferencesStore = .shared) -> String {
        switch prefs.engine {
        case .gemini: return "Gemini \(prefs.geminiModel.shortLabel)"
        case .whisper:
            switch prefs.modelID {
            case .parakeetUltra: return "Parakeet Ultra"
            case .turbo:         return "Whisper Turbo"
            case .small:         return "Whisper Small"
            case .tiny:          return "Whisper Tiny"
            }
        }
    }

    /// "Parakeet Ultra on this Mac" / "Gemini 3.5 Transcribe".
    static func summary(_ prefs: PreferencesStore = .shared) -> String {
        prefs.engine == .gemini ? modelName(prefs) : "\(modelName(prefs)) on this Mac"
    }

    /// "Parakeet · on this Mac" for the transcribing HUD.
    static func short(_ prefs: PreferencesStore = .shared) -> String {
        if prefs.engine == .gemini { return "Gemini" }
        return prefs.modelID.isParakeet ? "Parakeet · on this Mac" : "Whisper · on this Mac"
    }

    /// The first hotkey's short name, e.g. "Right ⌥".
    static func hotkey(_ prefs: PreferencesStore = .shared) -> String { short(prefs.hotkey) }

    /// "Right Option" → "Right ⌥"; key combos keep their label.
    static func short(_ b: HotkeyBinding) -> String {
        guard b.kind == .modifier else { return b.label }
        return b.label
            .replacingOccurrences(of: "Option", with: "⌥")
            .replacingOccurrences(of: "Command", with: "⌘")
            .replacingOccurrences(of: "Control", with: "⌃")
            .replacingOccurrences(of: "Shift", with: "⇧")
    }

    /// "Right ⌥ Option" for the shortcut recorder.
    static func keycap(_ b: HotkeyBinding) -> String {
        guard b.kind == .modifier else { return b.label }
        let side = b.label.split(separator: " ").first.map(String.init) ?? ""
        let name = b.label.split(separator: " ").dropFirst().joined(separator: " ")
        let sym = short(b).split(separator: " ").last.map(String.init) ?? ""
        return "\(side) \(sym) \(name)"
    }
}
