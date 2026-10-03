import AppKit
import AVFoundation
import Combine
import SwiftUI
@preconcurrency import UserNotifications

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
    private var modelsVM: ModelsViewModel!
    private var cancellables = Set<AnyCancellable>()
    /// Last values acted on, so unrelated defaults writes don't re-trigger them.
    private var appliedPrimaryLanguage: PrimaryLanguage?
    private var appliedModelID: WhisperModelID?
    private var appliedEngine: TranscriptionEngineKind?
    /// Bumped per recording, so a slow transcription can't close a newer HUD.
    private var hudGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PreferencesStore.shared.applyAppearance()
        Self.migrateLegacyAppSupportDirectory()

        do {
            store = try HistoryStore(url: HistoryStore.defaultURL())
        } catch {
            NSLog("Failed to open history DB: \(error)")
            NSApp.terminate(nil)
            return
        }
        metrics = MetricsEngine(store: store, resetAnchor: {
            Int64(PreferencesStore.shared.metricsResetAtMs)
        })
        recorder = AudioRecorder()
        engine = TranscriptionEngine()
        coordinator = TranscriptionCoordinator(engine: engine, store: store)
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
        menu = MenuBarController(viewModel: popoverVM)
        overlay = OverlayWindow(content: AnyView(hudView()))
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
        appliedModelID = prefs.modelID
        appliedEngine = prefs.engineChosen ? prefs.engine : nil
        // A fresh install loads nothing until onboarding picks an engine; Gemini
        // never needs the ~800 MB Whisper model in memory.
        if prefs.engineChosen, prefs.engine == .whisper {
            loadModel(prefs.modelID)
        }

        NotificationCenter.default.addObserver(forName: .openPreferences, object: nil, queue: .main) { [weak self] note in
            let tab = (note.object as? String).flatMap(PrefsTab.init(rawValue:)) ?? .general
            Task { @MainActor in self?.showPreferences(initialTab: tab) }
        }

        handlePermissionsAndStart()

        Task { await popoverVM.checkForUpdates() }
    }

    private func handlePermissionsAndStart() {
        hotkey.start()
        let perms = PermissionsManager.shared.current()
        if !perms.allGranted || !PreferencesStore.shared.engineChosen { showOnboarding() }
    }

    private func showOnboarding() {
        let content = OnboardingView(
            modelsVM: modelsVM,
            needsEngine: !PreferencesStore.shared.engineChosen,
            onEngineChosen: { [weak self] kind in self?.chooseEngine(kind) },
            onDone: { [weak self] in
                self?.onboardingWin?.close()
                self?.onboardingWin = nil
                self?.hotkey.start()
            }
        )
        let hc = NSHostingController(rootView: content)
        let win = NSWindow(contentViewController: hc)
        win.title = "Welcome"
        win.styleMask = [.titled, .closable]
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

    private func showPreferences(initialTab: PrefsTab = .general) {
        if prefsWin == nil { prefsWin = PreferencesWindowController() }
        let view = PreferencesView(
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
            initialTab: initialTab
        )
        prefsWin?.present(view)
    }

    @ViewBuilder private func hudView() -> some View {
        HUDPillView()
    }

    private func loadModel(_ modelID: WhisperModelID) {
        Task {
            pttLog("Preloading model: \(modelID.rawValue)")
            do {
                try await engine.preload(model: modelID)
                pttLog("Model loaded OK: \(modelID.rawValue)")
            } catch {
                pttLog("Model preload FAILED: \(error)")
            }
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
        TerminologyStore.shared.setActiveLanguage(code)
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
                self.overlay.hide()
                if case AudioRecorderError.stalled = error {
                    self.notify("Microphone not responding", "Audio was reset — try again.")
                }
            }
            .store(in: &cancellables)

    }

    private func startRecording() {
        pttLog("startRecording")
        hudGeneration += 1
        recorder.start(input: PreferencesStore.shared.inputSelection)
        overlay.update(AnyView(hudView()))
        overlay.show(anchor: menu.statusItemFrame)
    }

    private func cancelRecording() {
        pttLog("cancelRecording (tap shorter than hold threshold)")
        recorder.stop { [weak self] in
            _ = self?.engine.takeSamples() // discard the tap's audio
        }
        overlay.hide()
    }

    private func endRecording() {
        pttLog("endRecording")
        let generation = hudGeneration
        HUDAmplitudeModel.shared.setPhase(.processing)
        recorder.stop { [weak self] in
            guard let self else { return }
            // Take the samples now, synchronously: the next recording's chunks can
            // arrive on main as soon as this completion returns.
            let samples = self.engine.takeSamples()
            Task { @MainActor in
                let outcome = await self.coordinator.finishRecording(samples: samples)
                if case .inserted = outcome {
                    self.finishHUD(generation: generation, success: true)
                } else {
                    self.finishHUD(generation: generation, success: false)
                }
                switch outcome {
                case .empty:
                    return
                case .skippedSecureField:
                    self.notify("Skipped password field", "Transcript saved to history.")
                case .noFocus:
                    self.notify("No focused input", "Transcript saved to history.")
                case .inserted:
                    break
                case .failed(let failure):
                    self.overlay.flash(AnyView(HUDMessageView(title: failure.title, detail: failure.body)),
                                       anchor: self.menu.statusItemFrame,
                                       seconds: failure.displaySeconds)
                    return
                }
                self.popoverVM.refresh()
            }
        }
    }

    /// Shows a brief checkmark after a successful insert, then hides the HUD —
    /// unless another recording has started in the meantime.
    private func finishHUD(generation: Int, success: Bool) {
        guard generation == hudGeneration else { return }
        guard success else { overlay.hide(); return }
        HUDAmplitudeModel.shared.setPhase(.done)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, generation == self.hudGeneration else { return }
            self.overlay.hide()
        }
    }

    private static func migrateLegacyAppSupportDirectory() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = base.appendingPathComponent("push-to-talk")
        let target = base.appendingPathComponent("HoldSpeak")
        guard fm.fileExists(atPath: legacy.path),
              !fm.fileExists(atPath: target.path) else { return }
        do {
            try fm.moveItem(at: legacy, to: target)
            pttLog("Migrated Application Support: push-to-talk → HoldSpeak")
        } catch {
            pttLog("Migration failed: \(error)")
        }
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            if granted {
                UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
            }
        }
    }
}
