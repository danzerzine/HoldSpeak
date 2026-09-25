import Foundation
import SwiftUI


public enum AppTheme: String, CaseIterable, Identifiable {
    case auto, light, dark
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .auto:  return "Auto"
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }
    public var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        }
    }
}

public enum HUDPosition: String, CaseIterable, Identifiable {
    case underMenuBarIcon, bottomCenter
    public var id: String { rawValue }
    public var label: String {
        switch self { case .underMenuBarIcon: return "Under menu bar icon"; case .bottomCenter: return "Bottom center" }
    }
}

public enum PrimaryLanguage: String, CaseIterable, Identifiable {
    case auto
    case ar, zh, nl, en, fr, de, hi, it, ja, ko, pl, pt, ru, es, tr, uk

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .auto: return "Auto-detect"
        case .ar:   return "Arabic"
        case .zh:   return "Chinese"
        case .nl:   return "Dutch"
        case .en:   return "English"
        case .fr:   return "French"
        case .de:   return "German"
        case .hi:   return "Hindi"
        case .it:   return "Italian"
        case .ja:   return "Japanese"
        case .ko:   return "Korean"
        case .pl:   return "Polish"
        case .pt:   return "Portuguese"
        case .ru:   return "Russian"
        case .es:   return "Spanish"
        case .tr:   return "Turkish"
        case .uk:   return "Ukrainian"
        }
    }
    public var whisperCode: String? {
        self == .auto ? nil : rawValue
    }
}

public enum WhisperModelID: String, CaseIterable, Identifiable {
    case tiny = "openai_whisper-tiny"
    case small = "openai_whisper-small"
    case turbo = "openai_whisper-large-v3-v20240930"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .tiny:  return "Tiny (~40 MB)"
        case .small: return "Small (~250 MB)"
        case .turbo: return "Turbo — large-v3 distilled (~800 MB, recommended)"
        }
    }
}

public final class PreferencesStore: ObservableObject {
    @AppStorage("hotkeyBindingJSON") private var hotkeyBindingJSON: String = ""
    @AppStorage("holdThresholdMs") public var holdThresholdMs: Int = 150
    @AppStorage("hudPosition")     public var hudPosition: HUDPosition = .bottomCenter
    @AppStorage("modelID")         public var modelID: WhisperModelID = .turbo
    @AppStorage("primaryLanguage") public var primaryLanguage: PrimaryLanguage = .ru
    @AppStorage("launchAtLogin")   public var launchAtLogin: Bool = false
    @AppStorage("appTheme")        public var appTheme: AppTheme = .auto
    @AppStorage("autoPunctuation") public var autoPunctuation: Bool = true
    @AppStorage("autoCapitalize")  public var autoCapitalize: Bool = true
    @AppStorage("metricsResetAtMs") public var metricsResetAtMs: Int = 0
    @AppStorage("inputDevice")     private var inputDeviceRaw: String = InputSelection.avoidBluetooth.rawValue

    public var inputSelection: InputSelection {
        get { InputSelection(rawValue: inputDeviceRaw) }
        set { objectWillChange.send(); inputDeviceRaw = newValue.rawValue }
    }

    public func applyAppearance() {
        NSApp.appearance = appTheme.nsAppearance
    }

    /// Decoded `hotkey`, keyed by the JSON it came from. The event tap reads the
    /// binding on every system-wide key event, so avoid re-decoding each time.
    private var cachedHotkey: (json: String, binding: HotkeyBinding)?

    public var hotkey: HotkeyBinding {
        get {
            let json = hotkeyBindingJSON
            if let cached = cachedHotkey, cached.json == json { return cached.binding }
            let binding: HotkeyBinding
            if let data = json.data(using: .utf8),
               let b = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
                binding = b
            } else {
                let legacy = UserDefaults.standard.string(forKey: "hotkey")
                binding = legacy == "rightCmd" ? .rightCommand : .rightOption
            }
            cachedHotkey = (json, binding)
            return binding
        }
        set {
            objectWillChange.send()
            if let data = try? JSONEncoder().encode(newValue),
               let s = String(data: data, encoding: .utf8) {
                hotkeyBindingJSON = s
                cachedHotkey = (s, newValue)
            }
        }
    }

    public static let shared = PreferencesStore()
    private init() {}
}
