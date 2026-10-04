import SwiftUI
import AppKit

@MainActor
final class PopoverViewModel: ObservableObject {
    struct FailedDictation: Equatable {
        let title: String
        /// Length of the kept audio.
        let seconds: Int
        var at = Date()
    }

    @Published var metrics: Metrics = .zero
    @Published var recent: [TranscriptionRecord] = []
    /// Version of an update Sparkle found and the user hasn't installed yet.
    @Published var update: String?
    /// The last dictation's failure while its audio is kept for a retry.
    @Published var failedDictation: FailedDictation?
    @Published var toast: String?
    var onRetry: (() -> Void)?

    static let recentVisible = 4

    private let store: HistoryStoring
    private let metricsEngine: MetricsComputing

    init(store: HistoryStoring, metricsEngine: MetricsComputing) {
        self.store = store
        self.metricsEngine = metricsEngine
    }

    func refresh() {
        metrics = (try? metricsEngine.current(now: Date())) ?? .zero
        recent = (try? store.recent(limit: Self.recentVisible)) ?? []
    }

    func copy(_ record: TranscriptionRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.cleanedText, forType: .string)
        toast = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            if self?.toast == "Copied" { self?.toast = nil }
        }
    }
}

/// The menu bar popover (concept section "Поповер"): can I talk right now, what
/// did I just dictate, and the usual menu items.
struct PopoverView: View {
    @ObservedObject var vm: PopoverViewModel
    @ObservedObject private var prefs = PreferencesStore.shared
    @ObservedObject private var status = AppStatus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if status.needsSetup { permissionAlert }
            holdHint
            Separator()
            Text("Recent")
                .font(DS.calloutStrong)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.s4)
                .padding(.top, 6)
                .padding(.bottom, 2)
            recentList
            if hasStats { stats }
            Separator()
            if let upd = vm.update { updateRow(upd) }
            VStack(spacing: 0) {
                MenuRow("Show All History…") { openSettings(.history) }
                MenuRow("Settings…", shortcut: "⌘,") { openSettings(.general) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .padding(.horizontal, 6)
            Separator()
            MenuRow("Quit Speak!", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .padding(.horizontal, 6)
        }
        .font(DS.body)
        .padding(.vertical, 6)
        .frame(width: DS.popoverWidth)
        .overlay(alignment: .top) { toast }
        .modifier(PopoverChrome())
        .preferredColorScheme(prefs.appTheme.colorScheme)
    }

    private func openSettings(_ pane: SettingsPane) {
        NotificationCenter.default.post(name: .openPreferences, object: pane.rawValue)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            radioIcon
                .frame(width: 15, height: 15)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Speak!").font(.system(size: 13, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                }
                .font(DS.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s4)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        if status.needsSetup || !prefs.engineChosen { return DS.warn }
        if status.modelLoading { return Color.secondary }
        return DS.ok
    }

    private var statusText: String {
        if status.needsSetup || !prefs.engineChosen { return "Needs attention" }
        if status.modelLoading { return "Loading \(EngineText.modelName(prefs))…" }
        return "Ready · \(EngineText.summary(prefs))"
    }

    // MARK: Permission alert

    private var permissionAlert: some View {
        let mic = !status.permissions.microphone
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.warn)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(mic ? "Microphone access is off" : "Accessibility is off")
                    .fontWeight(.semibold)
                Text(mic ? "Speak! can’t hear you until macOS allows the microphone."
                         : "Speak! can hear you but can’t type into other apps.")
                    .font(DS.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings…") {
                    if mic {
                        Task {
                            if await !PermissionsManager.shared.requestMicrophone() {
                                PermissionsManager.shared.openMicrophoneSettings()
                            }
                            status.refreshPermissions()
                        }
                    } else {
                        PermissionsManager.shared.openAccessibilitySettings()
                    }
                }
                .controlSize(.small)
                .padding(.top, DS.s1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: DS.alertRadius).fill(DS.warn.opacity(0.16)))
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var holdHint: some View {
        HStack(spacing: 6) {
            Text("Hold")
            KeyCap(EngineText.hotkey(prefs))
            Text("to talk")
        }
        .font(DS.detail)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.s4)
        .padding(.top, DS.s1)
        .padding(.bottom, 2)
    }

    // MARK: Recent

    @ViewBuilder private var recentList: some View {
        VStack(spacing: 0) {
            if let failed = vm.failedDictation {
                FailedRow(failed: failed) { vm.onRetry?() }
            }
            if vm.recent.isEmpty && vm.failedDictation == nil {
                HStack(spacing: 4) {
                    Text("Nothing yet. Hold")
                    KeyCap(EngineText.hotkey(prefs))
                    Text("and speak.")
                }
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(vm.recent.enumerated()), id: \.element.id) { i, r in
                RecentRow(record: r,
                          separated: i > 0 || vm.failedDictation != nil,
                          onCopy: { vm.copy(r) },
                          onFix: { openSettings(.dictionary) })
            }
        }
        .padding(.horizontal, 6)
    }

    private var hasStats: Bool {
        vm.metrics.dictationsToday + vm.metrics.dictationsYesterday > 0 || vm.metrics.wpm7d > 0
    }

    private var stats: some View {
        Text("\(vm.metrics.dictationsToday) today · \(vm.metrics.dictationsYesterday) yesterday · \(vm.metrics.wpm7d) wpm over 7 days")
            .font(DS.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.s4)
            .padding(.vertical, DS.s1)
    }

    private func updateRow(_ version: String) -> some View {
        HStack(spacing: DS.s2) {
            Text("Speak! \(version) is available")
                .font(DS.detail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Install…") { AppUpdater.shared.checkForUpdates() }
                .dsProminent()
                .controlSize(.small)
        }
        .padding(.horizontal, DS.s4)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var toast: some View {
        if let text = vm.toast {
            Text(text)
                .font(DS.detail)
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .padding(.horizontal, 10)
                .padding(.vertical, DS.s1)
                .background(Capsule().fill(Color.primary))
                .padding(.top, DS.s3)
                .transition(.opacity)
        }
    }
}

// MARK: - Rows

private struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, DS.s4)
            .padding(.vertical, 6)
    }
}

/// Keyboard key name in a small cap, as in "Hold [Right ⌥] to talk".
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }
}

/// A menu item: highlighted in the accent colour on hover, like a system menu.
private struct MenuRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(hover ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                }
            }
            .foregroundStyle(hover ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, DS.s1)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct RecentRow: View {
    let record: TranscriptionRecord
    let separated: Bool
    let onCopy: () -> Void
    let onFix: () -> Void
    @State private var hover = false

    private var fixes: [(canonical: String, heard: String)] { DictionaryMarks.fixes(in: record) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(DictionaryMarks.marked(record.cleanedText, fixes.map(\.canonical)))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RelativeTime.short(record.createdAt))
                    .font(DS.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(hover ? 0 : 1)
            }
            if !record.inserted {
                Text("Not inserted — no text field was focused")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.rowRadius).fill(hover ? Color.primary.opacity(0.06) : .clear))
        .overlay(alignment: .top) {
            if separated && !hover {
                Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1).padding(.horizontal, 10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hover {
                HStack(spacing: DS.s1) {
                    IconButton(system: "doc.on.doc", label: "Copy", action: onCopy)
                    IconButton(system: "pencil", label: "Fix a term", action: onFix)
                }
                .padding(.trailing, DS.s2)
                .padding(.bottom, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hover = $0 }
        .help(fixes.isEmpty ? "" : "Fixed by the dictionary: " + fixes.map { "«\($0.heard)» → \($0.canonical)" }.joined(separator: ", "))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Copy", onCopy)
    }
}

private struct FailedRow: View {
    let failed: PopoverViewModel.FailedDictation
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Same layout as a Recent row: time top right, the action under it.
            HStack(alignment: .firstTextBaseline) {
                Text("\(failed.seconds / 60):\(String(format: "%02d", failed.seconds % 60)) of audio")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(RelativeTime.short(Int64(failed.at.timeIntervalSince1970 * 1000)))
                    .font(DS.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text("Not transcribed — \(failed.title)")
                }
                .font(.system(size: 11))
                .foregroundStyle(DS.tally)
                Spacer()
                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }
        }
        .padding(10)
    }
}

private struct IconButton: View {
    let system: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Helpers

/// Terms the dictionary replaced in a dictation, for the dotted underline.
@MainActor
enum DictionaryMarks {
    static func fixes(in r: TranscriptionRecord) -> [(canonical: String, heard: String)] {
        let store = TerminologyStore.shared
        let lang = r.language ?? store.dictationLanguage
        let raw = r.rawText.lowercased()
        var out: [(String, String)] = []
        for e in store.entries(for: lang) where r.cleanedText.contains(e.canonical)
            && !raw.contains(e.canonical.lowercased()) {
            if let heard = e.variants.first(where: { raw.contains($0.lowercased()) }) {
                out.append((e.canonical, heard))
            }
        }
        return out
    }

    static func marked(_ text: String, _ terms: [String]) -> AttributedString {
        var s = AttributedString(text)
        for term in terms {
            if let range = s.range(of: term) {
                s[range].underlineStyle = Text.LineStyle(pattern: .dot, color: .secondary)
            }
        }
        return s
    }
}

enum RelativeTime {
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    /// "10:38" today, "Yesterday", then "3 Oct".
    static func short(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time.string(from: d) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return date.string(from: d)
    }

    static func full(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time.string(from: d) }
        if cal.isDateInYesterday(d) { return "Yesterday \(time.string(from: d))" }
        return "\(date.string(from: d)) \(time.string(from: d))"
    }
}

/// On macOS 26+ NSPopover draws Liquid Glass itself, so the content stays clear;
/// older systems get the popover material.
private struct PopoverChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content.background(VisualEffectBackground(material: .popover))
        }
    }
}

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }
}

extension Notification.Name {
    static let openPreferences = Notification.Name("openPreferences")
}

/// Bundled SVG icons, loaded from disk once and shared by the popover and the
/// status item. Template images so they follow the menu bar / label tint.
enum BundledIcon {
    static let radio: NSImage? = load("radio")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        return img
    }
}

@ViewBuilder
var radioIcon: some View {
    if let img = BundledIcon.radio {
        Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
    } else {
        Image(systemName: "antenna.radiowaves.left.and.right").resizable().scaledToFit()
    }
}
