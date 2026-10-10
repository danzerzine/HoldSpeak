import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The wrong spelling waiting to be fixed: filled by the "Fix Spelling in Speak!"
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

/// Settings → Dictionary. The always-open "Transcribed as → Should be" row is the
/// main way to add a term (Return saves, no extra buttons); the table below lists
/// the dictionary of the language picked here, which doesn't change dictation.
struct DictionaryPane: View {
    @ObservedObject var store: TerminologyStore = .shared
    @ObservedObject var draft: CorrectionDraft = .shared

    private enum CorrectionField { case wrong, right }
    @State private var right: String = ""
    @State private var feedback: String?
    /// The last deleted entry and its position, while Undo is offered.
    @State private var removed: (entry: TerminologyEntry, index: Int)?
    @FocusState private var correctionFocus: CorrectionField?
    @State private var confirmingDefaults = false
    /// Terms read from a file, while the Add / Replace choice is open.
    @State private var pendingImport: [TerminologyEntry]?
    @State private var errorAlert: (title: String, detail: String)?

    @State private var editing: TerminologyEntry?
    @State private var selection = Set<TerminologyEntry.ID>()
    /// The search field in the Settings header.
    @Binding var searchText: String

    private var filteredEntries: [TerminologyEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.entries }
        let needle = q.lowercased()
        return store.entries.filter { entry in
            if entry.canonical.lowercased().contains(needle) { return true }
            return entry.variants.contains { $0.lowercased().contains(needle) }
        }
    }

    /// Languages the user keeps a dictionary for, plus the one they speak and
    /// the one open now. A bundled default alone (Ukrainian) doesn't add a tab.
    private var languages: [PrimaryLanguage] {
        var codes = store.savedLanguages()
        codes.insert(store.activeLanguage)
        if PreferencesStore.shared.primaryLanguage != .auto {
            codes.insert(PreferencesStore.shared.primaryLanguage.rawValue)
        }
        return PrimaryLanguage.allCases.filter { $0 != .auto && codes.contains($0.rawValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            HStack(spacing: DS.s3) {
                CompactSegmented(label: "Dictionary language",
                                 selection: Binding(get: { store.activeLanguage },
                                                    set: { store.setActiveLanguage($0) }),
                                 options: languages.map { ($0.rawValue, $0.label) })
                Text(store.entries.count == 1 ? "1 term" : "\(store.entries.count) terms")
                    .font(DS.detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            correctionRow

            VStack(spacing: 0) {
                Table(filteredEntries, selection: $selection) {
                    TableColumn("Heard as") { e in
                        Tags(words: e.variants)
                    }
                    TableColumn("Should be") { e in
                        Text(e.canonical)
                    }
                    .width(min: 120, ideal: 160)
                }
                .contextMenu(forSelectionType: TerminologyEntry.ID.self) { ids in
                    Button("Edit…") { edit(ids) }
                    Button("Delete") { removeSelected(ids) }
                } primaryAction: { ids in
                    edit(ids)
                }
                .onDeleteCommand { removeSelected(selection) }
                .overlay { emptyOverlay }

                Divider()
                tableFooter
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.groupRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.groupRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .padding(.horizontal, DS.s5)
        .padding(.bottom, DS.s5)
        .onAppear {
            // Open the dictionary dictation uses now, where a fix most likely belongs.
            store.setActiveLanguage(store.dictationLanguage)
            focusDraft()
        }
        .onChange(of: draft.request) {
            store.setActiveLanguage(store.dictationLanguage)
            focusDraft()
        }
        .onChange(of: store.activeLanguage) {
            searchText = ""; removed = nil; feedback = nil; selection = []
        }
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

    // MARK: Correction row

    private var correctionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                correctionField("Transcribed as", placeholder: "бойскап", text: $draft.wrong, field: .wrong) {
                    correctionFocus = .right
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 5)
                correctionField("Should be", placeholder: "Basecamp", text: $right, field: .right,
                                onSubmit: saveCorrection)
            }
            // Concept `.grp`: the always-open row sits in a grey group.
            .padding(.horizontal, DS.s3)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: DS.groupRadius).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: DS.groupRadius).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            HStack(spacing: 6) {
                Text(feedback ?? "Press Return to save. Or select a word in any app → Services → Fix Spelling in Speak!")
                    .font(DS.callout)
                    .foregroundStyle(.secondary)
                if let removed {
                    Button("Undo") {
                        store.restore(removed.entry, at: removed.index)
                        self.removed = nil
                        feedback = nil
                    }
                    .buttonStyle(.link)
                    .font(DS.callout)
                }
            }
        }
        .confirmationDialog("Load default IT dictionary?", isPresented: $confirmingDefaults) {
            Button("Merge") { store.loadDefaults(mergeStrategy: .skipExisting) }
            Button("Replace", role: .destructive) { store.loadDefaults(mergeStrategy: .replaceAll) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Merge adds missing entries. Replace discards your current list.")
        }
        .confirmationDialog("Import \(pendingImport?.count ?? 0) terms?", isPresented: importDialogShown) {
            Button("Add") { if let e = pendingImport { store.addMissing(e) } }
            Button("Replace", role: .destructive) { if let e = pendingImport { store.replaceAll(e) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add keeps your list and adds terms it doesn't have. Replace discards your current list.")
        }
        .alert(errorAlert?.title ?? "", isPresented: errorShown) {
            Button("OK") {}
        } message: {
            Text(errorAlert?.detail ?? "")
        }
        // Typing starts a new correction; clearing the fields after a save keeps the message.
        .onChange(of: draft.wrong) { _, new in if !new.isEmpty { feedback = nil; removed = nil } }
        .onChange(of: right) { _, new in if !new.isEmpty { feedback = nil; removed = nil } }
    }

    private func correctionField(_ label: String, placeholder: String, text: Binding<String>,
                                 field: CorrectionField, onSubmit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($correctionFocus, equals: field)
                .onSubmit(onSubmit)
        }
        .frame(maxWidth: .infinity)
    }

    private func focusDraft() {
        right = ""
        searchText = ""
        Task { @MainActor in correctionFocus = draft.wrong.isEmpty ? .wrong : .right }
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

    // MARK: Table

    @ViewBuilder private var emptyOverlay: some View {
        if store.entries.isEmpty {
            VStack(spacing: DS.s2) {
                Text("No terms yet for this language.").foregroundStyle(.secondary)
                if store.hasSeed(for: store.activeLanguage) {
                    Button("Load the Default IT Dictionary") { store.loadDefaults(mergeStrategy: .replaceAll) }
                }
            }
        } else if filteredEntries.isEmpty {
            Text("No terms match “\(searchText)”. Type it in the row above to add it.")
                .foregroundStyle(.secondary)
        }
    }

    private var tableFooter: some View {
        HStack(spacing: DS.s1) {
            Button { removeSelected(selection) } label: {
                Image(systemName: "minus").frame(width: 22, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection.isEmpty)
            .help("Delete the selected terms")

            Menu {
                Button("Load Default Dictionary…") { confirmingDefaults = true }
                    .disabled(!store.hasSeed(for: store.activeLanguage))
                Divider()
                Button("Import…", action: importJSON)
                Button("Export…", action: exportJSON)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Import, export or load the default dictionary")

            Spacer()
            Text("Double-click a row to edit")
                .font(DS.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, DS.s1)
        .background(Color.primary.opacity(0.035))
    }

    private func edit(_ ids: Set<TerminologyEntry.ID>) {
        guard let id = ids.first, let entry = store.entries.first(where: { $0.id == id }) else { return }
        editing = entry
    }

    private func removeSelected(_ ids: Set<TerminologyEntry.ID>) {
        let doomed = store.entries.filter { ids.contains($0.id) }
        guard !doomed.isEmpty else { return }
        if doomed.count == 1 {
            remove(doomed[0])
        } else {
            doomed.forEach { store.remove(id: $0.id) }
            removed = nil
            feedback = "Removed \(doomed.count) terms."
        }
        selection = []
    }

    // MARK: - Actions

    private func remove(_ entry: TerminologyEntry) {
        guard let index = store.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        store.remove(id: entry.id)
        removed = (entry, index)
        feedback = "Removed “\(entry.canonical)”."
    }

    private var importDialogShown: Binding<Bool> {
        Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })
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
                      "It isn't a Speak! dictionary export. (\(error.localizedDescription))")
            return
        }
        pendingImport = entries
    }

    private func showError(_ title: String, _ detail: String) {
        errorAlert = (title, detail)
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

/// Misheard variants as small tags (concept `.tag`): as many whole tags as fit, then "+N".
private struct Tags: View {
    let words: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: min(words.count, 6), through: 1, by: -1)), id: \.self) { n in
                row(n)
            }
        }
        .help(words.joined(separator: ", "))
    }

    private func row(_ n: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(words.prefix(n), id: \.self) { w in
                Text(w)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                    .fixedSize(horizontal: n > 1, vertical: false)
            }
            if words.count > n {
                Text("+\(words.count - n)").font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize()
            }
        }
    }
}

private struct EditorSheet: View {
    @State var entry: TerminologyEntry
    let onSave: (TerminologyEntry) -> Void
    let onCancel: () -> Void

    @State private var variantsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Term")
                .font(DS.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Should be")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("pull request", text: $entry.canonical)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcribed as (one per line)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextEditor(text: $variantsText)
                    .font(DS.detail)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
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
                .dsProminent()
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            variantsText = entry.variants.joined(separator: "\n")
        }
    }
}
