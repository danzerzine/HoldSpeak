import SwiftUI

/// Checks a Gemini API key with Google before saving it to the Keychain.
@MainActor
@Observable
final class GeminiKeyModel {
    enum Check { case idle, checking, invalid, unreachable, saveFailed }
    var draft = ""
    var check: Check = .idle

    static let keyPageURL = URL(string: "https://aistudio.google.com/apikey")!

    var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var problem: String? {
        switch check {
        case .invalid:     return "Google rejected this key"
        case .unreachable: return "Couldn’t reach Google — check your connection"
        case .saveFailed:  return "Couldn’t save the key to the Keychain"
        default:           return nil
        }
    }

    func save() {
        let key = trimmed
        guard !key.isEmpty, check != .checking else { return }
        check = .checking
        Task { @MainActor in
            switch await GeminiClient().check(apiKey: key) {
            case .valid:
                guard PreferencesStore.shared.saveGeminiAPIKey(key) else {
                    check = .saveFailed
                    return
                }
                draft = ""
                check = .idle
            case .invalid:
                check = .invalid
            case .unreachable:
                check = .unreachable
            }
        }
    }

    /// "AIza••••••••Q4"
    static func masked(_ key: String) -> String {
        guard key.count > 6 else { return String(repeating: "•", count: key.count) }
        return key.prefix(4) + String(repeating: "•", count: 8) + key.suffix(2)
    }
}

/// The API key row in Settings → Recognition: the saved key masked with Remove,
/// or a field to paste one.
struct GeminiKeyRow: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var model = GeminiKeyModel()

    var body: some View {
        if let key = prefs.geminiAPIKey, !key.isEmpty {
            LabeledContent {
                HStack(spacing: DS.s2) {
                    Text(GeminiKeyModel.masked(key))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("Remove") { prefs.geminiAPIKey = nil }
                }
            } label: {
                RowLabel("API key", "Verified with Google · stored in Keychain")
            }
        } else {
            LabeledContent {
                HStack(spacing: DS.s2) {
                    SecureField("Paste your key", text: $model.draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit(model.save)
                    Button(model.check == .checking ? "Checking…" : "Save", action: model.save)
                        .disabled(model.trimmed.isEmpty || model.check == .checking)
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("API key")
                    if let problem = model.problem {
                        Text(problem).font(DS.callout).foregroundStyle(DS.tally)
                    } else {
                        Link("Get a key in Google AI Studio", destination: GeminiKeyModel.keyPageURL)
                            .font(DS.callout)
                    }
                }
            }
        }
    }
}

/// The same, laid out for the onboarding card.
struct GeminiKeyField: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var model = GeminiKeyModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let key = prefs.geminiAPIKey, !key.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.ok)
                    Text("Key \(GeminiKeyModel.masked(key)) verified").foregroundStyle(.secondary)
                    Button("Remove") { prefs.geminiAPIKey = nil }.buttonStyle(.link)
                }
                .font(DS.callout)
            } else {
                HStack(spacing: DS.s2) {
                    SecureField("Paste your Gemini API key", text: $model.draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(model.save)
                    Button(model.check == .checking ? "Checking…" : "Save", action: model.save)
                        .disabled(model.trimmed.isEmpty || model.check == .checking)
                }
                Group {
                    if let problem = model.problem {
                        Text(problem).foregroundStyle(DS.tally)
                    } else {
                        Link("Get a key in Google AI Studio", destination: GeminiKeyModel.keyPageURL)
                    }
                }
                .font(DS.callout)
            }
        }
    }
}
