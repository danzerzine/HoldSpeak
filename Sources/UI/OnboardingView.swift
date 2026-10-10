import SwiftUI

/// First launch in four short steps (concept section "Первый запуск"): what the app
/// does, where to recognise speech, permissions (checked on their own while the
/// model downloads), and a first dictation to see it work.
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var modelsVM: ModelsViewModel
    @ObservedObject private var prefs = PreferencesStore.shared
    @ObservedObject private var status = AppStatus.shared
    @State private var step: Step
    @State private var choice: TranscriptionEngineKind
    @State private var tryText = ""
    @FocusState private var tryFocused: Bool
    @State private var holding = false
    /// Snapshot runs only: permissions to draw instead of the live ones.
    private let previewPermissions: Permissions?
    private var perms: Permissions { previewPermissions ?? status.permissions }

    /// Called when the user confirms an engine (a Gemini key is already saved by then).
    var onEngineChosen: (TranscriptionEngineKind) -> Void
    var onTryPress: () -> Void
    var onTryRelease: () -> Void
    var onDone: () -> Void

    enum Step: Int, CaseIterable { case welcome, engine, permissions, tryIt }

    init(modelsVM: ModelsViewModel,
         needsEngine: Bool,
         initialStep: Step? = nil,
         initialChoice: TranscriptionEngineKind? = nil,
         previewPermissions: Permissions? = nil,
         onEngineChosen: @escaping (TranscriptionEngineKind) -> Void,
         onTryPress: @escaping () -> Void,
         onTryRelease: @escaping () -> Void,
         onDone: @escaping () -> Void) {
        self.modelsVM = modelsVM
        self.onEngineChosen = onEngineChosen
        self.onTryPress = onTryPress
        self.onTryRelease = onTryRelease
        self.onDone = onDone
        // After a reinstall or rename only the permissions are missing: start there.
        _step = State(initialValue: initialStep ?? (needsEngine ? .welcome : .permissions))
        _choice = State(initialValue: initialChoice ?? (needsEngine ? .whisper : PreferencesStore.shared.engine))
        self.previewPermissions = previewPermissions
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome:     welcome
                case .engine:      engine
                case .permissions: permissions
                case .tryIt:       tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 56)
            .padding(.top, 54)
            .transition(.opacity)
            footer
        }
        .frame(width: 600, height: 470)
        .preferredColorScheme(prefs.appTheme.colorScheme)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            heading("Hold to talk. Release to type.",
                    "Hold a key, say what you want, let go. Speak! types it into whatever app you’re in — a terminal, a chat, a pull request.")
            HStack(spacing: DS.s2) {
                Circle().fill(DS.tally).frame(width: 7, height: 7)
                Text("Listening").fontWeight(.semibold)
                Text("0:03").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(DS.detail)
            .padding(.horizontal, DS.s3)
            .frame(height: 30)
            .dsGlass(Capsule(), classic: Capsule())
            .padding(.top, DS.s3)
            .accessibilityHidden(true)
        }
    }

    private var engine: some View {
        VStack(spacing: 0) {
            heading("Where should speech be recognized?",
                    "You can change this later in Settings → Recognition.")
            HStack(alignment: .top, spacing: DS.s3) {
                EngineCard(symbol: "laptopcomputer", title: "On this Mac",
                           detail: "Parakeet Ultra. Free, private, works offline. Downloads 610 MB.",
                           selected: choice == .whisper) { choice = .whisper }
                EngineCard(symbol: "cloud", title: "Gemini",
                           detail: "Google cloud. Better with mixed languages. Needs your API key with billing.",
                           selected: choice == .gemini) { choice = .gemini }
            }
            .padding(.top, 22)
            if choice == .gemini {
                GeminiKeyField().padding(.top, DS.s3)
            }
            Form {
                Picker("I mostly speak", selection: $prefs.primaryLanguage) {
                    ForEach(PrimaryLanguage.allCases) { Text($0.label).tag($0) }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 64)
            .padding(.horizontal, -20)
            .padding(.top, 2)
        }
    }

    private var permissions: some View {
        VStack(spacing: 0) {
            heading("Allow Speak! to listen and type",
                    "macOS asks once for each. Speak! notices the change on its own.")
            Form {
                permissionRow("Microphone", "To hear you while you hold the key",
                              granted: perms.microphone, button: "Allow…") {
                    Task {
                        if await !PermissionsManager.shared.requestMicrophone() {
                            PermissionsManager.shared.openMicrophoneSettings()
                        }
                        status.refreshPermissions()
                    }
                }
                permissionRow("Accessibility", "To type the text into the app you’re using",
                              granted: perms.accessibility, button: "Open Settings…") {
                    PermissionsManager.shared.openAccessibilitySettings()
                }
                permissionRow("Input Monitoring", "To notice when you hold \(EngineText.hotkey(prefs))",
                              granted: perms.inputMonitoring, button: "Open Settings…") {
                    PermissionsManager.shared.openInputMonitoringSettings()
                    status.refreshPermissions()
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 190)
            .padding(.horizontal, -20)
            .padding(.top, 8)
            if !requiredAllowed {
                Text("Microphone and Accessibility are needed to continue. Input Monitoring can wait.")
                    .font(DS.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, DS.s1)
            }
            if modelsVM.downloading {
                HStack(spacing: 10) {
                    Text("Downloading \(EngineText.modelName(prefs)) — \(Int(modelsVM.progress * 100))%")
                        .font(DS.detail)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: modelsVM.progress)
                }
                .padding(.top, DS.s3)
            }
        }
        .onAppear { status.refreshPermissions() }
    }

    private var tryIt: some View {
        VStack(spacing: 0) {
            Text("Try it").font(DS.title).padding(.top, 14)
            HStack(spacing: 4) {
                Text("Click the field, hold")
                KeyCap(EngineText.hotkey(prefs))
                Text("and say a sentence. Release to see it typed.")
            }
            .font(DS.body)
            .foregroundStyle(.secondary)
            .padding(.top, DS.s2)

            TextField("Your words will appear here", text: $tryText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4, reservesSpace: true)
                .focused($tryFocused)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tryFocused ? Color.accentColor : Color.primary.opacity(0.14),
                                  lineWidth: tryFocused ? 2 : 1))
                .padding(.top, 22)

            HStack(spacing: 14) {
                Text(holding ? "Listening… release to type" : "Hold to try")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(holding ? DS.tally : Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                    .foregroundStyle(holding ? Color.white : Color.primary)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !holding else { return }
                            holding = true
                            tryFocused = true
                            onTryPress()
                        }
                        .onEnded { _ in
                            holding = false
                            onTryRelease()
                        })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Hold to try")
                Button("Skip", action: onDone).buttonStyle(.link)
            }
            .padding(.top, DS.s3)
        }
        .onAppear { Task { @MainActor in tryFocused = true } }
    }

    private func heading(_ title: String, _ text: String) -> some View {
        VStack(spacing: DS.s2) {
            Text(title)
                .font(DS.title)
                .multilineTextAlignment(.center)
            Text(text)
                .font(DS.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 410)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14)
    }

    private func permissionRow(_ title: String, _ caption: String, granted: Bool, button: String,
                               action: @escaping () -> Void) -> some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DS.ok)
                    .font(.system(size: 12.5))
            } else {
                Button(button, action: action).dsProminent().controlSize(.small)
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(caption).font(DS.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Back") { if let prev = Step(rawValue: step.rawValue - 1) { step = prev } }
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            Button(step == .tryIt ? "Done" : "Continue", action: next)
                .keyboardShortcut(.defaultAction)
                .dsProminent()
                .disabled(!canContinue)
        }
        // Centred on the window, not between buttons of different widths.
        .overlay {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle()
                        .fill(s == step ? Color.primary : Color.primary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        }
        .padding(.horizontal, DS.s5)
        .padding(.vertical, DS.s4)
    }

    private var canContinue: Bool {
        switch step {
        case .welcome:     return true
        case .engine:      return choice == .whisper || prefs.hasGeminiKey
        case .permissions: return requiredAllowed
        case .tryIt:       return true
        }
    }

    private var requiredAllowed: Bool { perms.microphone && perms.accessibility }

    private func next() {
        switch step {
        case .welcome:
            step = .engine
        case .engine:
            onEngineChosen(choice)
            step = .permissions
        case .permissions:
            step = .tryIt
        case .tryIt:
            onDone()
        }
    }
}

/// One engine choice (concept `.card`).
private struct EngineCard: View {
    let symbol: String
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.s1) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 22)
                    .padding(.bottom, DS.s1)
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(DS.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: DS.cardRadius)
                .fill(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: DS.cardRadius)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.06), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: DS.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
