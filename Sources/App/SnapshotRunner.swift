import AppKit
import SwiftUI

/// Developer check: SPEAK_SNAPSHOT=/some/dir renders the main screens into PNGs
/// there and quits. Materials (glass, vibrancy) come out flat, but layout, text
/// and spacing are real, which is what an agent without screen access needs.
@MainActor
enum SnapshotRunner {
    static func run(into dir: String, modelsVM: ModelsViewModel, store: HistoryStore,
                    popoverVM: PopoverViewModel) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var jobs: [(String, AnyView, NSSize)] = []

        popoverVM.refresh()
        jobs.append(("popover", AnyView(PopoverView(vm: popoverVM)), NSSize(width: DS.popoverWidth, height: 600)))
        popoverVM.failedDictation = .init(title: "Gemini daily limit reached", seconds: 42)
        popoverVM.update = ReleaseInfo(version: "1.4", url: URL(string: "https://example.com")!)
        jobs.append(("popover-failed-update", AnyView(PopoverView(vm: popoverVM)), NSSize(width: DS.popoverWidth, height: 700)))

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
            prefs.pillColor = color
            for (name, content) in huds {
                jobs.append(("hud-\(color)-\(name)",
                             AnyView(HUDPill(content: content).padding(30)), NSSize(width: 640, height: 120)))
            }
        }

        for pane in SettingsPane.allCases {
            jobs.append(("settings-\(pane.rawValue)",
                         AnyView(SettingsView(modelsVM: modelsVM, historyStore: store, onClearHistory: {},
                                              onResetMetrics: {}, initialPane: pane)),
                         NSSize(width: 780, height: 540)))
        }
        for step in OnboardingView.Step.allCases {
            jobs.append(("onboarding-\(step.rawValue)",
                         AnyView(OnboardingView(modelsVM: modelsVM, needsEngine: true, initialStep: step,
                                                onEngineChosen: { _ in }, onTryPress: {}, onTryRelease: {}, onDone: {})),
                         NSSize(width: 600, height: 470)))
        }

        func next(_ i: Int) {
            guard i < jobs.count else {
                prefs.pillColor = savedPill
                pttLog("snapshot: wrote \(jobs.count) images to \(dir)")
                NSApp.terminate(nil)
                return
            }
            let (name, view, size) = jobs[i]
            let win = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
                               styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            win.titlebarAppearsTransparent = true
            win.contentView = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            win.orderFrontRegardless()
            // Let SwiftUI lay out and run onAppear before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let v = win.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
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
