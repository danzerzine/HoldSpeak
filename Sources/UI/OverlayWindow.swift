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
    /// What the panel shows now, unwrapped, so present() can measure it.
    private var content: AnyView
    /// The panel never gets smaller than this: the recording pill sits centred in it
    /// with room for its shadow, as before the merge with upstream.
    private static let minSize = NSSize(width: 420, height: 84)
    /// The transparent margin under the pill; the placement offsets it, keeping
    /// the pill where it used to sit.
    private static let shadowInset: CGFloat = 14

    init(prefs: PreferencesStore = .shared, content: AnyView) {
        self.prefs = prefs
        self.content = content
        panel = NSPanel(contentRect: .init(origin: .zero, size: Self.minSize),
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

    func update(_ content: AnyView) {
        self.content = content
        hosting.rootView = Self.centred(content)
    }

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
        // A long message can outgrow the pill's panel; measure the bare content (the
        // centring frame would report no size) and keep the panel fixed while shown.
        let fit = NSHostingView(rootView: content).fittingSize
        panel.setContentSize(NSSize(width: max(Self.minSize.width, fit.width),
                                    height: max(Self.minSize.height, fit.height)))
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
        let m = Self.shadowInset
        switch prefs.hudPosition {
        case .underMenuBarIcon:
            if let anchor {
                let x = anchor.midX - frame.width / 2
                let y = anchor.minY - frame.height - 6 + m
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                let vf = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: vf.maxX - frame.width - 16,
                                             y: vf.maxY - frame.height - 6 + m))
            }
        case .bottomCenter:
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.midX - frame.width / 2,
                                         y: vf.minY + 80 - m))
        }
    }
}
