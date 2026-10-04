import SwiftUI
import AppKit
import ServiceManagement

/// Settings sections in the sidebar (concept section "Settings в духе System Settings").
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcut, recognition, dictionary, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return "General"
        case .shortcut:    return "Shortcut"
        case .recognition: return "Recognition"
        case .dictionary:  return "Dictionary"
        case .history:     return "History"
        }
    }

    var symbol: String {
        switch self {
        case .general:     return "gearshape.fill"
        case .shortcut:    return "keyboard.fill"
        case .recognition: return "waveform"
        case .dictionary:  return "book.fill"
        case .history:     return "clock.fill"
        }
    }

    /// Words the sidebar search matches besides the title.
    var keywords: [String] {
        switch self {
        case .general:     return ["permissions", "microphone", "accessibility", "login", "theme", "appearance", "pill", "updates", "statistics"]
        case .shortcut:    return ["hotkey", "key", "push to talk", "option", "recording", "limit"]
        case .recognition: return ["engine", "model", "parakeet", "whisper", "gemini", "api key", "language", "microphone", "punctuation"]
        case .dictionary:  return ["terms", "words", "corrections", "spelling", "import", "export"]
        case .history:     return ["dictations", "recent", "clear"]
        }
    }

    /// Sidebar tile colour, as System Settings colours its icons.
    var tint: Color {
        switch self {
        case .general:     return Color(hex: 0x8e8e93)
        case .shortcut:    return Color(hex: 0x5e5ce6)
        case .recognition: return Color(hex: 0x0a84ff)
        case .dictionary:  return Color(hex: 0xff9f0a)
        case .history:     return Color(hex: 0x30b158)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var modelsVM: ModelsViewModel
    var historyStore: HistoryStoring
    var onClearHistory: () -> Void
    var onResetMetrics: () -> Void
    var initialPane: SettingsPane = .general

    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var pane: SettingsPane = .general
    /// The header search field of Dictionary and History.
    @State private var paneQuery = ""

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $pane)
            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Under the transparent titlebar: the traffic lights sit inside the sidebar and the
        // pane title on their row, as in the concept.
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 700, minHeight: 480)
        .preferredColorScheme(prefs.appTheme.colorScheme)
        .onAppear { pane = initialPane }
        .onChange(of: pane) { paneQuery = "" }
    }

    /// Pane title in the content column (concept `.ctop`): 52 high, 15 pt bold.
    private var header: some View {
        HStack(spacing: 10) {
            Text(pane.title)
                .font(DS.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if pane == .dictionary || pane == .history {
                SearchField(prompt: pane == .dictionary ? "Search terms" : "Search", text: $paneQuery)
                    .frame(width: 170)
            }
        }
        .padding(.horizontal, DS.s5)
        .frame(height: 52)
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .general:
            GeneralPane(onResetMetrics: onResetMetrics)
        case .shortcut:
            ShortcutPane()
        case .recognition:
            RecognitionPane(modelsVM: modelsVM)
        case .dictionary:
            DictionaryPane(searchText: $paneQuery)
        case .history:
            HistoryPane(store: historyStore, query: $paneQuery, onClear: onClearHistory)
        }
    }
}

/// Sidebar of the Settings window (concept `.side`): an inset glass panel on
/// macOS 26+, a full-height sidebar with a hairline on 14–15. Its search field
/// filters the sections; ↑/↓ move between them.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane
    @State private var query = ""
    @FocusState private var listFocused: Bool

    private var visible: [SettingsPane] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter { p in
            p.title.lowercased().contains(q) || p.keywords.contains { $0.contains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SearchField(prompt: "Search", text: $query)
                .padding(.horizontal, 2)
                .padding(.bottom, 10)
                .onSubmit { if let first = visible.first { selection = first } }
            ForEach(visible) { p in
                SidebarRow(pane: p, selected: p == selection) { selection = p }
            }
            Spacer(minLength: 0)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onMoveCommand(perform: move)
        // The traffic lights (top 22 on glass, 14 classic; 14 high) and 16 below them, concept `.side .lights`.
        .padding(.top, 44)
        .padding(.horizontal, 10)
        .padding(.bottom, DS.s3)
        .frame(width: DS.isGlass ? 194 : 210)
        .frame(maxHeight: .infinity)
        .background { sidebarBackground }
        .padding(DS.isGlass ? 8 : 0)
    }

    @ViewBuilder private var sidebarBackground: some View {
        if DS.isGlass {
            Color.clear.dsGlass(RoundedRectangle(cornerRadius: DS.groupRadius))
        } else {
            VisualEffectBackground(material: .sidebar)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                }
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        let list = visible
        guard let i = list.firstIndex(of: selection) else {
            if let first = list.first { selection = first }
            return
        }
        switch direction {
        case .up where i > 0:               selection = list[i - 1]
        case .down where i < list.count - 1: selection = list[i + 1]
        default: break
        }
    }
}

/// One section in the sidebar: colour tile and title; the chosen one is filled
/// with the accent colour and white text (concept `.nav[aria-current]`).
private struct SidebarRow: View {
    let pane: SettingsPane
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.s2) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(pane.tint))
                Text(pane.title)
                    .font(DS.body)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.s2)
            .padding(.vertical, DS.s1)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.05 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Small rounded search field (concept `.search` / `.ctop .field`).
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.s2)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Shared rows

/// A row label with a caption under it, as System Settings draws them.
struct RowLabel: View {
    let title: String
    var caption: String?
    init(_ title: String, _ caption: String? = nil) {
        self.title = title
        self.caption = caption
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            if let caption {
                Text(caption)
                    .font(DS.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A status (dot and text) in place of a row title, with a caption under it.
struct StatusRowLabel: View {
    let status: StatusDot
    let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            status
            Text(caption)
                .font(DS.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Green dot "Allowed", or an orange dot "Off" with a button to the right pane.
private struct PermissionRow: View {
    let title: String
    var caption: String?
    let granted: Bool
    let button: String
    let open: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                StatusDot(text: "Allowed", color: DS.ok)
            } else {
                HStack(spacing: DS.s2) {
                    StatusDot(text: "Off", color: DS.warn)
                    Button(button, action: open)
                }
            }
        } label: {
            RowLabel(title, caption)
        }
    }
}

struct StatusDot: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    var onResetMetrics: () -> Void
    @ObservedObject private var prefs = PreferencesStore.shared
    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionRow(title: "Microphone", granted: status.permissions.microphone, button: "Allow…") {
                    Task {
                        if await !PermissionsManager.shared.requestMicrophone() {
                            PermissionsManager.shared.openMicrophoneSettings()
                        }
                        status.refreshPermissions()
                    }
                }
                PermissionRow(title: "Accessibility", caption: "Needed to type text into other apps",
                              granted: status.permissions.accessibility, button: "Open…") {
                    PermissionsManager.shared.openAccessibilitySettings()
                }
                PermissionRow(title: "Input Monitoring", caption: "Needed for the push-to-talk key",
                              granted: status.permissions.inputMonitoring, button: "Open…") {
                    PermissionsManager.shared.openInputMonitoringSettings()
                }
            }

            Section {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin).controlSize(.small)
                    .onAppear(perform: syncLaunchAtLogin)
                    .onChange(of: prefs.launchAtLogin) { _, on in applyLaunchAtLogin(on) }
            }

            Section("Appearance") {
                LabeledContent("Theme") {
                    CompactSegmented(label: "Theme", selection: $prefs.appTheme,
                                     options: AppTheme.allCases.map { ($0, $0.label) })
                }
                .onChange(of: prefs.appTheme) { prefs.applyAppearance() }

                LabeledContent {
                    CompactSegmented(label: "Status pill", selection: $prefs.hudPosition,
                                     options: HUDPosition.allCases.map { ($0, $0.label) })
                } label: {
                    RowLabel("Status pill", "Where it appears while you speak")
                }

                LabeledContent("Pill color") {
                    Swatches(selection: $prefs.pillColor)
                }
            }

            Section("Updates") {
                LabeledContent {
                    Button("Check Now", action: checkForUpdates)
                } label: {
                    RowLabel("Speak! \(AppUpdater.currentVersion) (\(buildNumber))", updateText)
                }
            }

            Section {
                LabeledContent {
                    Button(action: confirmReset) { Text("Reset…").foregroundStyle(DS.tally) }
                } label: {
                    RowLabel("Statistics", "Dictations and words per minute in the menu")
                }
            }
        }
        .formStyle(.grouped)
        // The window colour behind the groups, as under the pane header.
        .scrollContentBackground(.hidden)
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var updateText: String {
        if let version = updater.availableVersion { return "Speak! \(version) is available" }
        guard let d = updater.lastCheck else { return "Checked automatically every day" }
        return "Checked \(RelativeTime.full(Int64(d.timeIntervalSince1970 * 1000)).lowercasedFirstIfDay)"
    }

    private func checkForUpdates() {
        updater.checkForUpdates()
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset statistics?"
        alert.informativeText = "Dictation counts and words per minute in the menu start from zero. History is kept."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { onResetMetrics() }
    }

    /// `.requiresApproval` counts as on: the item is registered, the user just has
    /// to allow it in System Settings → Login Items.
    private func syncLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        let on = status == .enabled || status == .requiresApproval
        if prefs.launchAtLogin != on { prefs.launchAtLogin = on }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        let registered = service.status == .enabled || service.status == .requiresApproval
        do {
            if enabled, !registered {
                try service.register()
            } else if !enabled, registered {
                try service.unregister()
            }
        } catch {
            pttLog("Launch at login \(enabled ? "register" : "unregister") failed: \(error)")
        }
        syncLaunchAtLogin()
    }
}

private extension String {
    /// "Yesterday 09:12" → "yesterday 09:12"; a time alone gets "today at".
    var lowercasedFirstIfDay: String {
        if first?.isNumber == true, contains(":"), count <= 8 { return "today at \(self)" }
        if hasPrefix("Yesterday") { return "y" + dropFirst() }
        return self
    }
}

/// Round colour buttons for the status pill (concept `.swatches`).
private struct Swatches: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 7) {
            ForEach(PillColor.allCases) { c in
                Button { selection = c.rawValue } label: {
                    Circle()
                        .fill(c.fill.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Self.glassSwatch))
                        .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay {
                            if selection == c.rawValue {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(c.name)
                .accessibilityLabel(c.name)
                .accessibilityAddTraits(selection == c.rawValue ? .isSelected : [])
            }
        }
    }

    private static let glassSwatch = AngularGradient(
        colors: [Color(hex: 0xe9eef5), Color(hex: 0xcfd8e3), Color(hex: 0xf6f6f8), Color(hex: 0xd9e2ec), Color(hex: 0xe9eef5)],
        center: .center, angle: .degrees(210))
}

// MARK: - Shortcut

private struct ShortcutPane: View {
    @ObservedObject private var prefs = PreferencesStore.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Push to talk") { HotkeyRecorderView() }
                LabeledContent {
                    HStack(spacing: DS.s2) {
                        if prefs.hotkey2Enabled {
                            HotkeyRecorderView(second: true)
                            Button("Clear") { prefs.hotkey2Enabled = false }
                        } else {
                            Button("Add…") { prefs.hotkey2Enabled = true }
                        }
                    }
                } label: {
                    RowLabel("Second shortcut", "Handy on an external keyboard")
                }
            } footer: {
                Text("Click a shortcut and press the new key. A single letter or digit can’t be used: it would stop typing in every app.")
                    .font(DS.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    HStack(spacing: DS.s2) {
                        // Rounded in the setter rather than with `step:`, which draws
                        // a tick for every 10 ms on macOS 26+.
                        Slider(value: .init(get: { Double(prefs.holdThresholdMs) },
                                            set: { prefs.holdThresholdMs = Int(($0 / 10).rounded()) * 10 }),
                               in: 50...800)
                        Text("\(prefs.holdThresholdMs) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .frame(width: 220)
                } label: {
                    RowLabel("Ignore presses shorter than", "Quick taps and ⌥-letter combos won’t turn on the microphone")
                }
            }

            Section {

                Picker(selection: $prefs.maxRecordingMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("30 minutes").tag(30)
                    Divider()
                    Text("Never").tag(0)
                } label: {
                    RowLabel("Stop recording after", "Protects against a stuck key")
                }
            }
        }
        .formStyle(.grouped)
        // The window colour behind the groups, as under the pane header.
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Recognition

private struct RecognitionPane: View {
    @ObservedObject var modelsVM: ModelsViewModel
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var inputDevices: [InputDevice.Info] = []

    var body: some View {
        Form {
            Section("Engine") {
                EngineOption(title: "On this Mac", caption: "Free and private. Works offline.",
                             selected: prefs.engine == .whisper) { prefs.engine = .whisper }
                EngineOption(title: "Gemini", caption: "Google cloud with your API key. Better with mixed languages.",
                             selected: prefs.engine == .gemini) { prefs.engine = .gemini }
            }

            if prefs.engine == .whisper {
                localSection
            } else {
                geminiSection
            }

            Section {
                Picker(selection: $prefs.primaryLanguage) {
                    ForEach(PrimaryLanguage.allCases) { Text($0.label).tag($0) }
                } label: {
                    RowLabel("Language", "Auto chooses among the languages in Language & Region")
                }
                Picker(selection: $prefs.inputSelection) {
                    Text(inputLabel(.avoidBluetooth)).tag(InputSelection.avoidBluetooth)
                    Text(inputLabel(.systemDefault)).tag(InputSelection.systemDefault)
                    if !inputDevices.isEmpty { Divider() }
                    ForEach(inputDevices) { d in
                        Text(d.isContinuity ? "\(d.name) (slow to start)" : d.name)
                            .tag(InputSelection.device(uid: d.uid))
                    }
                    if case .device(let uid) = prefs.inputSelection, !inputDevices.contains(where: { $0.uid == uid }) {
                        Text("Disconnected device").tag(prefs.inputSelection)
                    }
                } label: {
                    RowLabel("Microphone", "A Bluetooth mic makes headphone audio stutter")
                }
                Toggle(isOn: $prefs.duckOutput) {
                    RowLabel("Quiet speakers while recording", "Music from the speakers drops to 20% so it stays out of the mic")
                }
                .controlSize(.small)
            }

            Section("Text") {
                Toggle("Capitalize first letter", isOn: $prefs.autoCapitalize).controlSize(.small)
                Toggle("End with a period", isOn: $prefs.autoPunctuation).controlSize(.small)
            }
        }
        .formStyle(.grouped)
        // The window colour behind the groups, as under the pane header.
        .scrollContentBackground(.hidden)
        .onAppear {
            loadInputDevices()
            modelsVM.refreshManagedSize()
        }
    }

    @ViewBuilder private var localSection: some View {
        Section {
            Picker("Model", selection: $prefs.modelID) {
                ForEach(WhisperModelID.allCases) { m in
                    Text(Self.modelLabel(m)).tag(m)
                }
            }
            if modelsVM.downloading {
                LabeledContent {
                    ProgressView(value: modelsVM.progress).frame(width: 160)
                } label: {
                    RowLabel("Downloading…", "\(Int(modelsVM.progress * 100))%")
                }
            } else if modelsVM.isLocated(prefs.modelID) {
                LabeledContent {
                    if modelsVM.managedBytes > 0 {
                        Button(action: confirmDeleteModels) { Text("Delete…").foregroundStyle(DS.tally) }
                    }
                } label: {
                    StatusRowLabel(status: StatusDot(text: "Downloaded", color: DS.ok), caption: modelsVM.managedBytes > 0
                             ? "Stored in Application Support · \(ByteCountFormatter.string(fromByteCount: modelsVM.managedBytes, countStyle: .file))"
                             : "Found in another app’s folder")
                }
            } else {
                LabeledContent {
                    Button("Download") { Task { await modelsVM.download(prefs.modelID) } }
                } label: {
                    RowLabel("Not downloaded", "Download it once to dictate offline")
                }
            }
        }
    }

    @ViewBuilder private var geminiSection: some View {
        Section {
            Picker("Model", selection: $prefs.geminiModel) {
                ForEach(GeminiModelID.allCases) { Text($0.shortLabel).tag($0) }
            }
            GeminiKeyRow()
        } footer: {
            HStack(spacing: 4) {
                Text("Audio is sent to Google. Without billing on the key, Gemini stops after a couple dozen dictations a day.")
                Link("Pricing", destination: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!)
            }
            .font(DS.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// "Parakeet Ultra · 610 MB", "Whisper Small · 470 MB" (concept `.pick`).
    static func modelLabel(_ m: WhisperModelID) -> String {
        let name = m.shortLabel.replacingOccurrences(of: " (~", with: " · ").replacingOccurrences(of: ")", with: "")
        return m.isParakeet ? name : "Whisper \(name)"
    }

    private func loadInputDevices() {
        DispatchQueue.global(qos: .userInitiated).async {
            let devices = InputDevice.inputDevices()
            DispatchQueue.main.async { inputDevices = devices }
        }
    }

    private func inputLabel(_ selection: InputSelection) -> String {
        switch selection {
        case .systemDefault: return "System default"
        case .avoidBluetooth: return "Built-in if default is Bluetooth"
        case .device(let uid):
            return inputDevices.first(where: { $0.uid == uid })?.name ?? "Disconnected device"
        }
    }

    private func confirmDeleteModels() {
        let size = ByteCountFormatter.string(fromByteCount: modelsVM.managedBytes, countStyle: .file)
        let alert = NSAlert()
        alert.messageText = "Delete downloaded models?"
        alert.informativeText = "Frees \(size). Only models Speak! downloaded are removed — copies from MacWhisper or other apps stay. You can download a model again at any time."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            modelsVM.deleteManagedModels()
        }
    }
}

/// One choice of a radio group, with a caption (concept `.radio`).
private struct EngineOption: View {
    let title: String
    let caption: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                RowLabel(title, caption)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - History

private struct HistoryPane: View {
    let store: HistoryStoring
    @Binding var query: String
    let onClear: () -> Void
    @State private var rows: [TranscriptionRecord] = []
    @State private var selection = Set<TranscriptionRecord.ID>()

    private var filtered: [TranscriptionRecord] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { $0.cleanedText.lowercased().contains(q) }
    }

    var body: some View {
        // Table and its footer in one rounded box (concept `.tblbox`).
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                TableColumn("Time") { r in
                    Text(RelativeTime.full(r.createdAt))
                        .font(DS.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .width(96)
                TableColumn("Text") { r in
                    Text(r.cleanedText).lineLimit(2).help(r.cleanedText)
                }
                .width(min: 120, ideal: 180)
                TableColumn("Words") { r in
                    Text("\(r.wordCount)").font(DS.caption).foregroundStyle(.secondary)
                }
                .width(54)
                TableColumn("Result") { r in
                    StatusDot(text: r.inserted ? "Inserted" : "Not inserted", color: r.inserted ? DS.ok : DS.warn)
                        .font(DS.callout)
                }
                .width(96)
            }
            .contextMenu(forSelectionType: TranscriptionRecord.ID.self) { ids in
                Button("Copy") { copy(ids) }
                Button("Fix a Term…") {
                    NotificationCenter.default.post(name: .openPreferences, object: SettingsPane.dictionary.rawValue)
                }
            } primaryAction: { ids in
                copy(ids)
            }
            .overlay {
                if filtered.isEmpty {
                    Text(rows.isEmpty ? "No dictations yet." : "No dictations contain “\(query)”.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Text("Double-click a row to copy it; right-click to fix a term")
                    .font(DS.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: confirmClear) {
                    Text("Clear History…").foregroundStyle(rows.isEmpty ? Color.secondary : DS.tally)
                }
                .controlSize(.small)
                .disabled(rows.isEmpty)
            }
            .padding(.leading, DS.s3)
            .padding(.trailing, 6)
            .padding(.vertical, DS.s1)
            .background(Color.primary.opacity(0.035))
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.groupRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.groupRadius)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, DS.s5)
        .padding(.bottom, DS.s5)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .historyDidChange)) { _ in load() }
    }

    private func load() {
        rows = (try? store.recent(limit: HistoryStore.maxEntries)) ?? []
    }

    private func copy(_ ids: Set<TranscriptionRecord.ID>) {
        let text = filtered.filter { ids.contains($0.id) }.map(\.cleanedText).joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear all dictation history?"
        alert.informativeText = "This can’t be undone. Statistics in the menu are kept."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onClear()
            rows = []
        }
    }
}

// MARK: - Window

final class PreferencesWindowController: NSWindowController {
    /// Renamed with the own sidebar shell, so a size saved by the old
    /// NavigationSplitView window (720 wide) is not restored.
    private static let frameName = "SpeakSettingsWindow"

    convenience init() {
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        host.sizingOptions = [.minSize]
        let win = NSWindow(contentViewController: host)
        win.title = "Settings"
        // No toolbar or title: the sidebar runs to the top edge under the
        // traffic lights and each pane draws its own header (concept `.win`).
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.titlebarSeparatorStyle = .none
        win.setContentSize(NSSize(width: 780, height: 540))
        self.init(window: win)
        // Opens where the user left it; the first time, centred.
        if !win.setFrameUsingName(Self.frameName) { win.center() }
        win.setFrameAutosaveName(Self.frameName)
        // AppKit puts the buttons back on every titlebar layout, so they are moved again after each.
        for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didExitFullScreenNotification] {
            NotificationCenter.default.addObserver(forName: name, object: win, queue: .main) { [weak self] _ in
                self?.placeTrafficLights()
            }
        }
    }

    /// Traffic lights inside the sidebar (concept `.side .lights`): the sidebar's
    /// inset and padding plus the lights' own 2/6 padding.
    private func placeTrafficLights() {
        guard let win = window,
              let close = win.standardWindowButton(.closeButton),
              let mini = win.standardWindowButton(.miniaturizeButton),
              let zoom = win.standardWindowButton(.zoomButton),
              let container = close.superview?.superview else { return }
        let origin = DS.isGlass ? CGPoint(x: 24, y: 22) : CGPoint(x: 16, y: 14)
        let height = close.frame.height + 2 * origin.y
        var bar = container.frame
        bar.size.height = height
        bar.origin.y = win.frame.height - height
        container.frame = bar
        let step = mini.frame.minX - close.frame.minX
        for (i, button) in [close, mini, zoom].enumerated() {
            button.setFrameOrigin(CGPoint(x: origin.x + CGFloat(i) * step, y: origin.y))
        }
    }

    func present<V: View>(_ view: V) {
        if let host = window?.contentViewController as? NSHostingController<AnyView> {
            host.rootView = AnyView(view)
        }
        showWindow(nil)
        placeTrafficLights()
        NSApp.activate(ignoringOtherApps: true)
    }
}
