import AppKit
import SwiftUI

/// Developer check: SPEAK_SNAPSHOT=/some/dir renders the main screens into PNGs
/// there and quits. Materials (glass, vibrancy) come out flat, but layout, text
/// and spacing are real, which is what an agent without screen access needs.
@MainActor
enum SnapshotRunner {
    /// A fresh history in the temp folder, filled with a busy day of dictation
    /// to agents: what the README screenshots show instead of the user's own history.
    static func demoStore() throws -> HistoryStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speak-demo-history.sqlite")
        try? FileManager.default.removeItem(at: url)
        let store = try HistoryStore(url: url)
        let now = Date().timeIntervalSince1970
        let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let recent: [(minutesAgo: Double, text: String, inserted: Bool)] = [
            (1, "Посмотри, почему падает CI на этом pull request. Похоже, миграция в Postgres не откатилась после теста.", true),
            (4, "Сделай rebase на main и поправь конфликты в Kubernetes манифестах, values для Helm chart не трогай.", true),
            (9, "Add a loading state to the settings screen and keep the current layout as is.", true),
            (16, "Напиши тест на парсер дат: кейс с пустой строкой сейчас не покрыт.", true),
            (23, "Вынеси retry логику из GeminiAPI в отдельный модуль и покрой её тестами.", true),
        ]
        // Older filler for today's and yesterday's counters; 0.4 s per word is a steady 150 wpm.
        let pool = [
            "Обнови README: добавь раздел про установку через Homebrew.",
            "Check why the Docker build takes four minutes, cache the npm install layer.",
            "Переименуй endpoint в users/me и обнови клиент на TypeScript.",
            "Сделай code review этого diff, особенно обработку ошибок в middleware.",
            "Add a Redis cache in front of the search endpoint with a five minute TTL.",
            "Почини flaky тест в интеграционных, он падает раз в десять прогонов.",
            "Сгенерируй миграцию: новое поле archived в таблице projects, по умолчанию false.",
            "Explain what this regex does and rewrite it so a human can read it.",
        ]
        var n = 0
        func filler(_ at: TimeInterval) throws {
            n += 1
            let text = pool[n % pool.count]
            let words = text.split(separator: " ").count
            _ = try store.append(TranscriptionRecord(createdAt: Int64(at * 1000), rawText: text, cleanedText: text,
                                                     durationMs: words * 400, wordCount: words, language: "ru", inserted: true))
        }
        for i in 0..<58 { try filler(max(todayStart + 60, now - 1800 - Double(i) * 300)) }
        for i in 0..<51 { try filler(todayStart - 3600 * 2 - Double(i) * 600) }
        for i in 0..<180 { try filler(todayStart - 86400 * 2 - Double(i) * 1500) }
        for r in recent.reversed() {
            let words = r.text.split(separator: " ").count
            _ = try store.append(TranscriptionRecord(createdAt: Int64((now - r.minutesAgo * 60) * 1000),
                                                     rawText: r.text, cleanedText: r.text,
                                                     durationMs: words * 400, wordCount: words,
                                                     language: "ru", inserted: r.inserted))
        }
        return store
    }

    static func run(into dir: String, modelsVM: ModelsViewModel, store: HistoryStore,
                    popoverVM: PopoverViewModel) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // `prep` runs right before its job renders: shared state (pill colour,
        // popover extras) set while building the list would leak into every job.
        var jobs: [(name: String, view: AnyView, size: NSSize, prep: () -> Void)] = []

        popoverVM.refresh()
        jobs.append(("popover", AnyView(PopoverView(vm: popoverVM)), NSSize(width: DS.popoverWidth, height: 600), {
            popoverVM.failedDictation = nil
            popoverVM.update = nil
        }))
        jobs.append(("popover-failed-update", AnyView(PopoverView(vm: popoverVM)), NSSize(width: DS.popoverWidth, height: 700), {
            popoverVM.failedDictation = .init(title: "Gemini daily limit reached", seconds: 42)
            popoverVM.update = "1.4"
        }))

        let levels: [CGFloat] = (0..<HUDAmplitudeModel.sampleCount).map { CGFloat(($0 * 37) % 10) / 10 }
        for scheme in [ColorScheme.light, .dark] {
            for state in [AppStatus.IconState.ready, .listening, .transcribing, .loading, .attention, .error] {
                jobs.append(("icon-\(scheme == .dark ? "dark" : "light")-\(state)",
                             AnyView(StatusItemView(state: state, levels: levels, time: 0.3, pop: nil)
                                .padding(6).environment(\.colorScheme, scheme)),
                             NSSize(width: 80, height: 34), {}))
            }
        }

        let huds: [(String, HUDContent)] = [
            ("listening", .listening),
            ("transcribing", .transcribing),
            ("nofield", .message(.warn, title: "No text field — nothing typed", detail: "Saved to history. Open the menu to copy it")),
            ("error", .message(.error, title: "Gemini daily limit reached", detail: TranscriptionFailure.quotaExceeded(daily: true, retryAfterSeconds: nil).body)),
            ("lock", .message(.lock, title: "Password field — nothing typed", detail: "The text wasn’t saved to history either")),
            ("loading", .message(.loading, title: "Loading Parakeet Ultra", detail: "First start after an update takes about 20 seconds. Audio is kept")),
        ]
        let prefs = PreferencesStore.shared
        let savedPill = prefs.pillColor
        for color in ["glass", "black"] {
            for (name, content) in huds {
                jobs.append(("hud-\(color)-\(name)",
                             AnyView(HUDPill(content: content).padding(30)), NSSize(width: 640, height: 120),
                             {
                                 prefs.pillColor = color
                                 // Two words and the start of a third, as a voice looks mid-sentence.
                                 let speech: [CGFloat] = [0.05, 0.1, 0.35, 0.7, 0.9, 0.75, 0.5, 0.65, 0.85, 0.6,
                                                          0.3, 0.12, 0.08, 0.25, 0.55, 0.8, 0.95, 0.7, 0.45, 0.6,
                                                          0.75, 0.5, 0.2, 0.1, 0.3, 0.6]
                                 HUDAmplitudeModel.shared.showForSnapshot(speech)
                             }))
            }
        }

        for pane in SettingsPane.allCases {
            jobs.append(("settings-\(pane.rawValue)",
                         AnyView(SettingsView(modelsVM: modelsVM, historyStore: store, onClearHistory: {},
                                              onResetMetrics: {}, initialPane: pane)),
                         NSSize(width: 780, height: 540), {}))
        }
        for step in OnboardingView.Step.allCases {
            jobs.append(("onboarding-\(step.rawValue)",
                         AnyView(OnboardingView(modelsVM: modelsVM, needsEngine: true, initialStep: step,
                                                onEngineChosen: { _ in }, onTryPress: {}, onTryRelease: {}, onDone: {})),
                         NSSize(width: 600, height: 470), {}))
        }
        jobs.append(("onboarding-1-gemini",
                     AnyView(OnboardingView(modelsVM: modelsVM, needsEngine: true, initialStep: .engine, initialChoice: .gemini,
                                            onEngineChosen: { _ in }, onTryPress: {}, onTryRelease: {}, onDone: {})),
                     NSSize(width: 600, height: 470), {}))
        let wasDownloading = modelsVM.downloading
        jobs.append(("onboarding-2-missing",
                     AnyView(OnboardingView(modelsVM: modelsVM, needsEngine: true, initialStep: .permissions,
                                            previewPermissions: Permissions(microphone: true, accessibility: false,
                                                                            inputMonitoring: false, documentsAccess: false),
                                            onEngineChosen: { _ in }, onTryPress: {}, onTryRelease: {}, onDone: {})),
                     NSSize(width: 600, height: 470), {
                         modelsVM.downloading = true
                         modelsVM.progress = 0.34
                     }))

        func next(_ i: Int) {
            guard i < jobs.count else {
                prefs.pillColor = savedPill
                modelsVM.downloading = wasDownloading
                pttLog("snapshot: wrote \(jobs.count) images to \(dir)")
                NSApp.terminate(nil)
                return
            }
            let (name, view, size, prep) = jobs[i]
            prep()
            let win = KeyWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            // Borderless: no titlebar inset above the content.
            win.contentView = NSHostingView(rootView: view
                .background(Color(nsColor: .windowBackgroundColor)))
            // Only Settings needs a key window (its switches); onboarding renders blank in one.
            if name.hasPrefix("settings") {
                NSApp.activate(ignoringOtherApps: true)
                win.makeKeyAndOrderFront(nil)
            } else {
                win.orderFrontRegardless()
            }
            // Let SwiftUI lay out and run onAppear before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // Always 2x, whatever screen the window landed on: README images need Retina pixels.
                if let v = win.contentView,
                   let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * 2),
                                              pixelsHigh: Int(v.bounds.height * 2), bitsPerSample: 8,
                                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                    rep.size = v.bounds.size
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: out.appendingPathComponent("\(name).png"))
                }
                win.orderOut(nil)
                next(i + 1)
            }
        }
        next(0)
    }
}

/// Borderless windows refuse key status by default; the snapshots need it.
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
