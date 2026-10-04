import AppKit
import AVFoundation
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkey: HotkeyMonitor!
    private var recorder: AudioRecorder!
    private var engine: TranscriptionEngine!
    private var coordinator: TranscriptionCoordinator!
    private var store: HistoryStore!
    private var metrics: MetricsEngine!
    private var overlay: OverlayWindow!
    private var menu: MenuBarController!
    private var popoverVM: PopoverViewModel!
    private var prefsWin: PreferencesWindowController?
    private var onboardingWin: NSWindow?
    private let status = AppStatus.shared
    /// True between the hotkey press and the end of capture; a release after the
    /// recording limit already stopped it is ignored.
    private var isRecording = false
    private var limitTimer: Timer?
    private var modelsVM: ModelsViewModel!
    private var cancellables = Set<AnyCancellable>()
    /// Last values acted on, so unrelated defaults writes don't re-trigger them.
    private var appliedPrimaryLanguage: PrimaryLanguage?
    private var appliedModelID: WhisperModelID?
    private var appliedEngine: TranscriptionEngineKind?
    /// Bumped per recording, so a slow transcription can't close a newer HUD.
    private var hudGeneration = 0

    /// Developer check: HOLDSPEAK_CHECK_FILES=a.wav:b.wav transcribes the files with
    /// Parakeet into Speak.log and quits; no menu bar item, hotkey or UI.
    private func runFileCheck(_ paths: [String]) {
        Task { @MainActor in
            do {
                try await engine.preload(model: .parakeetUltra)
                await engine.checkFiles(paths)
            } catch {
                pttLog("check: model load failed: \(error)")
            }
            pttLog("check: done")
            try? await Task.sleep(nanoseconds: 500_000_000)  // let the log queue flush
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.migrateFromHoldSpeak()
        PreferencesStore.shared.migrateRedesignDefaults()
        PreferencesStore.shared.applyAppearance()

        // SPEAK_SNAPSHOT + SPEAK_DEMO: README screenshots from a throwaway history, never the real one.
        let env = ProcessInfo.processInfo.environment
        let demo = env["SPEAK_SNAPSHOT"] != nil && env["SPEAK_DEMO"] != nil
        do {
            store = try demo ? SnapshotRunner.demoStore() : HistoryStore(url: HistoryStore.defaultURL())
        } catch {
            pttLog("Failed to open history DB: \(error)")
            NSApp.terminate(nil)
            return
        }
        metrics = MetricsEngine(store: store, resetAnchor: {
            demo ? 0 : Int64(PreferencesStore.shared.metricsResetAtMs)
        })
        recorder = AudioRecorder()
        engine = TranscriptionEngine()
        coordinator = TranscriptionCoordinator(engine: engine, store: store)
        if let files = ProcessInfo.processInfo.environment["HOLDSPEAK_CHECK_FILES"] {
            runFileCheck(files.split(separator: ":").map(String.init))
            return
        }
        modelsVM = ModelsViewModel()
        modelsVM.onDownloaded = { [weak self] id in
            let prefs = PreferencesStore.shared
            guard prefs.engine == .whisper, id == prefs.modelID else { return }
            self?.loadModel(id)
        }
        modelsVM.onDeleted = { [weak self] in
            guard let self else { return }
            self.engine.unloadWhisper()
            // The selected model may still be found in another app's folder.
            let prefs = PreferencesStore.shared
            if prefs.engine == .whisper, ModelManager.shared.locateModel(prefs.modelID) != nil {
                self.loadModel(prefs.modelID)
            }
        }
        popoverVM = PopoverViewModel(store: store, metricsEngine: metrics)
        popoverVM.onRetry = { [weak self] in self?.retryFailedDictation() }
        if let dir = ProcessInfo.processInfo.environment["SPEAK_SNAPSHOT"] {
            SnapshotRunner.run(into: dir, modelsVM: modelsVM, store: store, popoverVM: popoverVM)
            return
        }
        menu = MenuBarController(viewModel: popoverVM)
        overlay = OverlayWindow()
        hotkey = HotkeyMonitor()

        bind()
        applyPrimaryLanguageToTerminology()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDefaultsChange() }
        }

        // Installs from before the engine choice existed downloaded a Whisper model
        // on first launch: keep them on Whisper instead of asking again.
        let prefs = PreferencesStore.shared
        if !prefs.engineChosen, ModelManager.shared.hasManagedModels() {
            prefs.engine = .whisper
        }
        // Turbo was the default before Parakeet: an existing install that never
        // picked a model keeps it instead of downloading Parakeet on update.
        if prefs.engineChosen, UserDefaults.standard.object(forKey: "modelID") == nil {
            prefs.modelID = .turbo
        }
        // Russian was the default before the system language: keep it for them too.
        if prefs.engineChosen, UserDefaults.standard.object(forKey: "primaryLanguage") == nil {
            prefs.primaryLanguage = .ru
        }
        appliedModelID = prefs.modelID
        appliedEngine = prefs.engineChosen ? prefs.engine : nil
        // A fresh install loads nothing until onboarding picks an engine; Gemini
        // never needs the ~1.5 GB Whisper model in memory.
        if prefs.engineChosen, prefs.engine == .whisper {
            loadModel(prefs.modelID)
        }

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        NotificationCenter.default.addObserver(forName: .openPreferences, object: nil, queue: .main) { [weak self] note in
            let pane = (note.object as? String).flatMap(SettingsPane.init(rawValue:)) ?? .general
            Task { @MainActor in self?.showPreferences(initialPane: pane) }
        }

        handlePermissionsAndStart()

        AppUpdater.shared.$availableVersion
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.popoverVM.update = $0 }
            .store(in: &cancellables)
        AppUpdater.shared.start()
    }

    private func handlePermissionsAndStart() {
        hotkey.start()
        // Input Monitoring isn't required to start: the event tap runs on Accessibility.
        let perms = PermissionsManager.shared.current()
        if !perms.microphone || !perms.accessibility || !PreferencesStore.shared.engineChosen { showOnboarding() }
    }

    private func showOnboarding() {
        let content = OnboardingView(
            modelsVM: modelsVM,
            needsEngine: !PreferencesStore.shared.engineChosen,
            onEngineChosen: { [weak self] kind in self?.chooseEngine(kind) },
            onTryPress: { [weak self] in self?.startRecording() },
            onTryRelease: { [weak self] in self?.endRecording() },
            onDone: { [weak self] in
                self?.onboardingWin?.close()
                self?.onboardingWin = nil
                self?.hotkey.start()
            }
        )
        let hc = NSHostingController(rootView: content)
        let win = NSWindow(contentViewController: hc)
        win.title = "Welcome to Speak!"
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWin = win
    }

    private func chooseEngine(_ kind: TranscriptionEngineKind) {
        let prefs = PreferencesStore.shared
        prefs.engine = kind
        appliedEngine = kind
        appliedModelID = prefs.modelID
        pttLog("Engine chosen in onboarding: \(kind.rawValue)")
        guard kind == .whisper else { return }
        if ModelManager.shared.locateModel(prefs.modelID) != nil {
            loadModel(prefs.modelID)
        } else {
            // Shows progress in onboarding; onDownloaded loads it.
            Task { await modelsVM.download(prefs.modelID) }
        }
    }

    /// "Fix Spelling in Speak!" service (NSServices in Info.plist): the selected
    /// text becomes the wrong spelling on the Terms tab, ready for the right one.
    @objc func fixSpelling(_ pboard: NSPasteboard, userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        CorrectionDraft.shared.start(with: text)
        showPreferences(initialPane: .dictionary)
    }

    private func showPreferences(initialPane: SettingsPane = .general) {
        if prefsWin == nil { prefsWin = PreferencesWindowController() }
        let view = SettingsView(
            modelsVM: modelsVM,
            historyStore: store,
            onClearHistory: { [weak self] in
                try? self?.store.clear()
                self?.popoverVM.refresh()
            },
            onResetMetrics: { [weak self] in
                PreferencesStore.shared.metricsResetAtMs = Int(Date().timeIntervalSince1970 * 1000)
                self?.popoverVM.refresh()
            },
            initialPane: initialPane
        )
        prefsWin?.present(view.id(UUID()))
    }

    private var modelLoads = 0

    private func loadModel(_ modelID: WhisperModelID) {
        modelLoads += 1
        status.modelLoading = true
        Task {
            pttLog("Preloading model: \(modelID.rawValue)")
            do {
                try await engine.preload(model: modelID)
                pttLog("Model loaded OK: \(modelID.rawValue)")
            } catch {
                pttLog("Model preload FAILED: \(error)")
            }
            modelLoads -= 1
            if modelLoads == 0 { status.modelLoading = false }
        }
    }

    private func handleDefaultsChange() {
        let prefs = PreferencesStore.shared
        if prefs.primaryLanguage != appliedPrimaryLanguage {
            applyPrimaryLanguageToTerminology()
        }
        guard prefs.engineChosen else { return }
        let engineChanged = prefs.engine != appliedEngine
        if engineChanged {
            appliedEngine = prefs.engine
            pttLog("Engine switched to \(prefs.engine.rawValue)")
            if prefs.engine == .gemini { engine.unloadWhisper() }
        }
        guard prefs.engine == .whisper else { return }
        if engineChanged || prefs.modelID != appliedModelID {
            appliedModelID = prefs.modelID
            // A model that isn't on disk yet loads once "Download selected model" finishes.
            if ModelManager.shared.locateModel(prefs.modelID) != nil {
                loadModel(prefs.modelID)
            } else {
                pttLog("Model \(prefs.modelID.rawValue) selected but not downloaded — waiting for download")
            }
        }
    }

    private func applyPrimaryLanguageToTerminology() {
        let pref = PreferencesStore.shared.primaryLanguage
        appliedPrimaryLanguage = pref
        guard let code = pref.whisperCode else { return } // auto → let per-utterance detection drive
        TerminologyStore.shared.setDictationLanguage(code)
    }

    private func bind() {
        hotkey.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .startHold:  self.startRecording()
                case .endHold:    self.endRecording()
                case .cancelHold: self.cancelRecording()
                }
            }
            .store(in: &cancellables)

        recorder.amplitude
            .receive(on: DispatchQueue.main)
            .sink { amp in
                HUDAmplitudeModel.shared.push(amp)
            }
            .store(in: &cancellables)

        recorder.chunks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buf in
                self?.engine.feed(buf)
            }
            .store(in: &cancellables)

        recorder.failures
            .sink { [weak self] error in
                pttLog("Recorder failure: \(error)")
                guard let self else { return }
                // Capture died mid-recording (a headset unplugged): drop what it fed, or
                // the next dictation would start with this half-take. A stalled stop is
                // different: endRecording already ended it and transcribes those samples.
                let wasRecording = self.isRecording
                if wasRecording { _ = self.engine.takeSamples() }
                self.stopLimitTimer()
                self.isRecording = false
                self.status.phase = .idle
                if case AudioRecorderError.stalled = error {
                    self.showMessage(.error, "Microphone not responding",
                                     "Audio was reset. Hold the key and try again", seconds: 4)
                } else if wasRecording {
                    self.showMessage(.error, "Microphone stopped",
                                     "The recording was lost. Hold the key and try again", seconds: 4)
                } else {
                    self.overlay.hide()
                }
            }
            .store(in: &cancellables)

    }

    private var hudAnchor: CGRect? { menu.statusItemFrame }
    private var hudScreen: NSScreen? { menu.statusItemScreen }

    private func showMessage(_ kind: HUDMessageKind, _ title: String, _ detail: String, seconds: Double) {
        overlay.flash(.message(kind, title: title, detail: detail),
                      anchor: hudAnchor, screen: hudScreen, seconds: seconds)
    }

    private func startRecording() {
        guard !isRecording else { return }
        pttLog("startRecording")
        isRecording = true
        hudGeneration += 1
        recorder.start(input: PreferencesStore.shared.inputSelection)
        status.phase = .listening
        overlay.show(.listening, anchor: hudAnchor, screen: hudScreen)
        startLimitTimer()
    }

    private func cancelRecording() {
        guard isRecording else { return }
        pttLog("cancelRecording (tap shorter than hold threshold)")
        isRecording = false
        stopLimitTimer()
        recorder.stop { [weak self] in
            _ = self?.engine.takeSamples() // discard the tap's audio
        }
        status.phase = .idle
        overlay.hide()
    }

    private func endRecording() {
        guard isRecording else { return }
        pttLog("endRecording")
        isRecording = false
        stopLimitTimer()
        let generation = hudGeneration
        status.phase = .transcribing
        overlay.update(.transcribing)
        recorder.stop { [weak self] in
            guard let self else { return }
            // Take the samples now, synchronously: the next recording's chunks can
            // arrive on main as soon as this completion returns.
            let samples = self.engine.takeSamples()
            Task { @MainActor in await self.transcribe(samples, generation: generation) }
        }
    }

    /// Stops a recording that runs past the limit (a stuck key, a forgotten hold).
    private func startLimitTimer() {
        stopLimitTimer()
        let minutes = PreferencesStore.shared.maxRecordingMinutes
        guard minutes > 0 else { return }
        let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor in
                pttLog("Recording limit reached (\(minutes) min)")
                self?.endRecording()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        limitTimer = t
    }

    private func stopLimitTimer() {
        limitTimer?.invalidate()
        limitTimer = nil
    }

    /// Audio of the last dictation that failed to transcribe, kept for one retry.
    private var failedSamples: [Float]?

    private func retryFailedDictation() {
        guard let samples = failedSamples else { return }
        pttLog("retryFailedDictation")
        menu.closePopoverAndReturnFocus()
        hudGeneration += 1
        let generation = hudGeneration
        status.phase = .transcribing
        overlay.show(.transcribing, anchor: hudAnchor, screen: hudScreen)
        Task { @MainActor in await self.transcribe(samples, generation: generation) }
    }

    private func transcribe(_ samples: [Float], generation: Int) async {
        let outcome = await self.coordinator.finishRecording(samples: samples)
        let current = generation == hudGeneration
        if current { status.phase = .idle }
        switch outcome {
        case .failed(let failure):
            failedSamples = samples
            popoverVM.failedDictation = .init(title: failure.title, seconds: samples.count / 16_000)
            status.lastDictationFailed = true
        case .empty:
            break // silence: keep any earlier failure available for retry
        default:
            failedSamples = nil
            popoverVM.failedDictation = nil
        }
        guard current else { popoverVM.refresh(); return }
        switch outcome {
        case .empty:
            overlay.hide()
            return
        case .inserted:
            status.inserted()
            overlay.hide()
        case .skippedSecureField:
            showMessage(.lock, "Password field — nothing typed",
                        "The text wasn’t saved to history either", seconds: 4)
        case .noFocus:
            if !status.permissions.accessibility {
                showMessage(.warn, "Accessibility is off",
                            "Open the menu to fix it — the text is in history", seconds: 5)
            } else {
                showMessage(.warn, "No text field — nothing typed",
                            "Saved to history. Open the menu to copy it", seconds: 4)
            }
        case .failed(let failure):
            if failure == .whisperModelNotReady, status.modelLoading {
                showMessage(.loading, "Loading \(EngineText.modelName())",
                            "First start after an update takes about 20 seconds. Audio is kept", seconds: 5)
            } else {
                showMessage(.error, failure.title, failure.body, seconds: failure.displaySeconds)
            }
        }
        popoverVM.refresh()
    }

    /// First launch as Speak!: settings, files and the login item come over from
    /// HoldSpeak (a different bundle id, so macOS asks for permissions again).
    private static func migrateFromHoldSpeak() {
        do {
            if let from = try AppPaths.migrateSupportDirectory() {
                pttLog("Migrated Application Support: \(from) → Speak")
            }
        } catch {
            pttLog("Application Support migration failed: \(error)")
        }
        let copied = AppPaths.migrateDefaults(from: AppPaths.previousDefaults(), into: .standard)
        guard copied else { return }
        pttLog("Migrated settings from \(AppPaths.previousBundleID)")
        if UserDefaults.standard.bool(forKey: "launchAtLogin") {
            do { try SMAppService.mainApp.register() } catch {
                pttLog("Launch at login re-register failed: \(error)")
            }
        }
    }
}
