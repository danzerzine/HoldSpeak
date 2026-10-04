import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The wrong spelling waiting to be fixed: filled by the "Fix in HoldSpeak"
/// service so the Terms tab opens with it already typed in.
@MainActor
final class CorrectionDraft: ObservableObject {
    static let shared = CorrectionDraft()
    @Published var wrong = ""
    /// Bumped on every request so the tab refocuses even for the same word.
    @Published var request = 0

    func start(with wrong: String) {
        self.wrong = wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        request += 1
    }
}

struct TerminologyPreferencesView: View {
    @ObservedObject var store: TerminologyStore = .shared
    @ObservedObject var draft: CorrectionDraft = .shared
    @Environment(\.colorScheme) private var scheme

    private enum CorrectionField { case wrong, right }
    @State private var right: String = ""
    @State private var feedback: String?
    /// The last deleted entry and its position, while Undo is offered.
    @State private var removed: (entry: TerminologyEntry, index: Int)?
    @FocusState private var correctionFocus: CorrectionField?

    @State private var editing: TerminologyEntry?
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool
    @State private var importExportWidth: CGFloat = 180

    private var filteredEntries: [TerminologyEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.entries }
        let needle = q.lowercased()
        return store.entries.filter { entry in
            if entry.canonical.lowercased().contains(needle) { return true }
            return entry.variants.contains { $0.lowercased().contains(needle) }
        }
    }

    private static let languagePickerWidth: CGFloat = 180

    private struct ImportExportWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            correctionRow
            searchField
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        Color.clear
                            .frame(height: 0)
                            .id("resultsTop")
                        if store.entries.isEmpty {
                            emptyState
                        } else if filteredEntries.isEmpty {
                            noMatchesState
                        } else {
                            ForEach(filteredEntries) { entry in
                                row(entry)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: searchText) { _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo("resultsTop", anchor: .top)
                    }
                }
            }
            footer
        }
        .onAppear {
            // Open the dictionary dictation uses now, where a fix most likely belongs.
            store.setActiveLanguage(store.dictationLanguage)
            focusDraft()
        }
        .onChange(of: draft.request) { _ in
            store.setActiveLanguage(store.dictationLanguage)
            focusDraft()
        }
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .onChange(of: store.activeLanguage) { _ in searchText = ""; removed = nil; feedback = nil }
        .sheet(item: $editing) { entry in
            EditorSheet(entry: entry) { updated in
                if store.entries.contains(where: { $0.id == updated.id }) {
                    store.update(updated)
                } else {
                    store.add(updated)
                }
                editing = nil
            } onCancel: {
                editing = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Terminology")
                    .font(.system(size: 13))
                    .foregroundColor(PTT.textBody(scheme))
                Text("When a word comes out wrong, type what you got and what it should be.")
                    .font(.system(size: 11))
                    .foregroundColor(PTT.textSoft(scheme))
            }
            Spacer(minLength: 0)
            languagePicker
        }
    }

    private var correctionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                correctionField("Transcribed as", placeholder: "бойскап",
                                text: $draft.wrong, field: .wrong) {
                    correctionFocus = .right
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundColor(PTT.textMuted(scheme))
                    .padding(.top, 16)
                correctionField("Should be", placeholder: "Basecamp",
                                text: $right, field: .right, onSubmit: saveCorrection)
            }
            HStack(spacing: 6) {
                Text(feedback ?? "Press Return to save.")
                    .font(.system(size: 11))
                    .foregroundColor(PTT.textSoft(scheme))
                if let removed {
                    Button("Undo") {
                        store.restore(removed.entry, at: removed.index)
                        self.removed = nil
                        feedback = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }
        }
        // Typing starts a new correction; clearing the fields after a save keeps the message.
        .onChange(of: draft.wrong) { if !$0.isEmpty { feedback = nil; removed = nil } }
        .onChange(of: right) { if !$0.isEmpty { feedback = nil; removed = nil } }
    }

    private func correctionField(_ label: String, placeholder: String, text: Binding<String>,
                                 field: CorrectionField, onSubmit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(PTT.textMuted(scheme))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(PTT.textBody(scheme))
                .focused($correctionFocus, equals: field)
                .onSubmit(onSubmit)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .pttSurface(glass: Capsule(), fallback: RoundedRectangle(cornerRadius: 8),
                            fill: PTT.fieldBG(scheme), border: PTT.fieldBorder(scheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func focusDraft() {
        guard !draft.wrong.isEmpty else { return }
        right = ""
        searchText = ""
        DispatchQueue.main.async { correctionFocus = .right }
    }

    private func saveCorrection() {
        let wrong = draft.wrong.trimmingCharacters(in: .whitespacesAndNewlines)
        switch store.addCorrection(wrong: draft.wrong, right: right) {
        case .addedVariant(let canonical):
            feedback = "Saved: “\(wrong)” now becomes “\(canonical)”."
        case .newTerm:
            feedback = "Saved: “\(wrong)” now becomes “\(right.trimmingCharacters(in: .whitespaces))”."
        case .alreadyThere:
            feedback = "Already in the list."
        case .invalid:
            correctionFocus = draft.wrong.trimmingCharacters(in: .whitespaces).isEmpty ? .wrong : .right
            return
        }
        draft.wrong = ""
        right = ""
        correctionFocus = .wrong
    }

    private var languagePicker: some View {
        let binding = Binding<String>(
            get: { store.activeLanguage },
            set: { store.setActiveLanguage($0) }
        )
        let languages = PrimaryLanguage.allCases.filter { $0 != .auto }
        let currentLabel = languages.first(where: { $0.rawValue == store.activeLanguage })?.label
            ?? store.activeLanguage.uppercased()
        return VStack(alignment: .trailing, spacing: 4) {
            Text("Dictionary for")
                .font(.system(size: 11))
                .foregroundColor(PTT.textMuted(scheme))
            StyledDropdown(selection: binding, width: importExportWidth, current: currentLabel) {
                ForEach(languages) { lang in
                    Text(lang.label).tag(lang.rawValue)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No terms yet for this language.")
                .font(.system(size: 13))
                .foregroundColor(PTT.textMuted(scheme))
            if store.hasSeed(for: store.activeLanguage) {
                Button { store.loadDefaults(mergeStrategy: .replaceAll) } label: {
                    pillText("Load default IT dictionary")
                }.pttButton()
            } else {
                Text("No default dictionary is bundled for this language — add terms manually.")
                    .font(.system(size: 11))
                    .foregroundColor(PTT.textSoft(scheme))
            }
        }
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(PTT.textMuted(scheme))
            TextField("Search terms", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(PTT.textBody(scheme))
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(PTT.textMuted(scheme))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .pttSurface(glass: Capsule(), fallback: RoundedRectangle(cornerRadius: 8),
                    fill: PTT.fieldBG(scheme), border: PTT.fieldBorder(scheme))
    }

    private var noMatchesState: some View {
        Text("No terms match “\(searchText)”.")
            .font(.system(size: 12))
            .foregroundColor(PTT.textSoft(scheme))
            .padding(.vertical, 8)
    }

    private func row(_ entry: TerminologyEntry) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                if !entry.variants.isEmpty {
                    Text(entry.variants.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundColor(PTT.textSoft(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(PTT.textMuted(scheme))
                }
                Text(entry.canonical)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(PTT.textBody(scheme))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
            Button { editing = entry } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(PTT.textMuted(scheme))
            }.buttonStyle(.plain)
            Button { remove(entry) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(PTT.textMuted(scheme))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(PTT.cardBG(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PTT.surfaceBorder(scheme), lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { confirmLoadDefaults() } label: {
                pillText("Load defaults…")
            }.pttButton()

            Spacer()

            HStack(spacing: 8) {
                Button { importJSON() } label: {
                    pillText("Import…")
                }.pttButton()

                Button { exportJSON() } label: {
                    pillText("Export…")
                }.pttButton()
            }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: ImportExportWidthKey.self, value: g.size.width)
                }
            )
        }
        .onPreferenceChange(ImportExportWidthKey.self) { w in
            if w > 0 { importExportWidth = w }
        }
    }

    private func pillText(_ s: String) -> some View {
        Text(s)
    }

    // MARK: - Actions

    private func remove(_ entry: TerminologyEntry) {
        guard let index = store.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        store.remove(id: entry.id)
        removed = (entry, index)
        feedback = "Removed “\(entry.canonical)”."
    }

    private func confirmLoadDefaults() {
        let alert = NSAlert()
        alert.messageText = "Load default IT dictionary?"
        alert.informativeText = "Merge adds missing entries. Replace discards your current list."
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  store.loadDefaults(mergeStrategy: .skipExisting)
        case .alertSecondButtonReturn: store.loadDefaults(mergeStrategy: .replaceAll)
        default: break
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let entries: [TerminologyEntry]
        do {
            entries = try JSONDecoder().decode([TerminologyEntry].self, from: Data(contentsOf: url))
        } catch {
            showError("Couldn't read \(url.lastPathComponent)",
                      "It isn't a HoldSpeak dictionary export. (\(error.localizedDescription))")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Import \(entries.count) terms?"
        alert.informativeText = "Add keeps your list and adds terms it doesn't have. Replace discards your current list."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  store.addMissing(entries)
        case .alertSecondButtonReturn: store.replaceAll(entries)
        default: break
        }
    }

    private func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "terminology.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(store.entries).write(to: url)
        } catch {
            showError("Couldn't save \(url.lastPathComponent)", error.localizedDescription)
        }
    }
}

private struct EditorSheet: View {
    @State var entry: TerminologyEntry
    let onSave: (TerminologyEntry) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var variantsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit term")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PTT.textPrimary(scheme))

            VStack(alignment: .leading, spacing: 6) {
                Text("Should be")
                    .font(.system(size: 11))
                    .foregroundColor(PTT.textMuted(scheme))
                TextField("pull request", text: $entry.canonical)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcribed as (one per line)")
                    .font(.system(size: 11))
                    .foregroundColor(PTT.textMuted(scheme))
                TextEditor(text: $variantsText)
                    .font(.system(size: 12))
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(PTT.fieldBorder(scheme), lineWidth: 1))
            }

            Toggle("Case-sensitive", isOn: $entry.caseSensitive)
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let variants = variantsText
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    var e = entry
                    e.variants = variants
                    e.canonical = e.canonical.trimmingCharacters(in: .whitespaces)
                    guard !e.canonical.isEmpty else { return }
                    onSave(e)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            variantsText = entry.variants.joined(separator: "\n")
        }
    }
}
