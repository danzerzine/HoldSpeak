import AppKit
import SwiftUI

@MainActor
final class OverlayWindow {
    private let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private let prefs: PreferencesStore
    /// Bumped by every show/flash so a stale hide animation doesn't order out newer content.
    private var generation = 0
    private var flashHide: DispatchWorkItem?

    init(prefs: PreferencesStore = .shared, content: AnyView) {
        self.prefs = prefs
        panel = NSPanel(contentRect: .init(x: 0, y: 0, width: 420, height: 56),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hosting = NSHostingView(rootView: Self.centred(content))
        // Size the panel only in present(): if the hosting view resized it as the pill
        // shrinks from Listening to Transcribing, the pill would slide off-centre.
        hosting.sizingOptions = []
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting
    }

    func update(_ content: AnyView) { hosting.rootView = Self.centred(content) }

    private static func centred(_ content: AnyView) -> AnyView {
        AnyView(content.frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    func show(anchor menuBarIconFrame: CGRect?) {
        HUDAmplitudeModel.shared.start()
        present(anchor: menuBarIconFrame)
    }

    /// Shows `content` (a message, not the recording pill) for `seconds`, then hides.
    func flash(_ content: AnyView, anchor menuBarIconFrame: CGRect?, seconds: Double) {
        update(content)
        present(anchor: menuBarIconFrame)
        let hide = DispatchWorkItem { [weak self] in self?.hide() }
        flashHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: hide)
    }

    private func present(anchor: CGRect?) {
        flashHide?.cancel()
        flashHide = nil
        generation += 1
        // The recording pill and a message differ in size; fit the panel to whichever
        // is shown now, and keep it fixed while it is on screen.
        panel.setContentSize(hosting.fittingSize)
        reposition(anchor: anchor)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        HUDAmplitudeModel.shared.stop()
        let hiding = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == hiding else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func reposition(anchor: CGRect?) {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        // The content sits inside a transparent margin; place the visible capsule.
        let m = HUDChrome.margin
        switch prefs.hudPosition {
        case .underMenuBarIcon:
            if let anchor {
                let x = anchor.midX - frame.width / 2
                let y = anchor.minY - frame.height - 6 + m
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                let vf = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: vf.maxX - frame.width - 16 + m,
                                             y: vf.maxY - frame.height - 6 + m))
            }
        case .bottomCenter:
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - frame.width / 2,
                                         y: vf.minY + 80 - m))
        }
    }
}
