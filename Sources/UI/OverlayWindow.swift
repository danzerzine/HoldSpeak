import AppKit
import SwiftUI

/// A transparent, click-through panel that hosts the HUD. It stays one fixed size;
/// the pill inside is placed and animated by SwiftUI (HUDView), so it can grow from
/// "Listening" to a two-line message without the window jumping.
@MainActor
final class OverlayWindow {
    private let panel: NSPanel
    private let prefs: PreferencesStore
    private let model = HUDModel.shared
    /// Bumped by every show so a stale hide doesn't order out newer content.
    private var generation = 0
    private var flashHide: Task<Void, Never>?

    private static let size = NSSize(width: 640, height: 120)
    /// Gap between the menu bar icon and the pill.
    nonisolated static let topInset: CGFloat = 6
    /// Room under the bottom pill for its shadow.
    nonisolated static let bottomInset: CGFloat = 30
    /// The bottom pill's lower edge, above the Dock: where the old black pill sat.
    private static let bottomLift: CGFloat = 86

    init(prefs: PreferencesStore = .shared) {
        self.prefs = prefs
        panel = NSPanel(contentRect: .init(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: HUDView())
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
    }

    /// Shows (or switches) the HUD to `content`, anchored to the menu bar icon.
    func show(_ content: HUDContent, anchor: CGRect?, screen: NSScreen?) {
        flashHide?.cancel()
        flashHide = nil
        generation += 1
        if content == .listening { HUDAmplitudeModel.shared.start() }
        if content != model.content || !model.shown { Announce.say(content.announcement) }
        place(anchor: anchor, screen: screen)
        panel.appearance = prefs.appTheme.nsAppearance
        model.content = content
        if !panel.isVisible { panel.orderFrontRegardless() }
        model.shown = true
    }

    /// Shows a message for `seconds`, then hides.
    func flash(_ content: HUDContent, anchor: CGRect?, screen: NSScreen?, seconds: Double) {
        show(content, anchor: anchor, screen: screen)
        flashHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Switches the content in place, if the HUD is up.
    func update(_ content: HUDContent) {
        guard model.shown else { return }
        if content != .listening { HUDAmplitudeModel.shared.stop() }
        if content != model.content { Announce.say(content.announcement) }
        model.content = content
    }

    func hide() {
        HUDAmplitudeModel.shared.stop()
        let hiding = generation
        model.shown = false
        // Let the retract animation finish before the panel goes away.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.generation == hiding, !self.model.shown else { return }
            self.panel.orderOut(nil)
        }
    }

    private func place(anchor: CGRect?, screen: NSScreen?) {
        model.position = prefs.hudPosition
        let size = Self.size
        switch prefs.hudPosition {
        case .underMenuBarIcon:
            guard let screen = screen ?? NSScreen.main else { return }
            let sf = screen.frame
            // Without an icon frame (hidden by a menu bar manager) use the top-right corner.
            let iconMidX = anchor?.midX ?? (sf.maxX - 120)
            let top = anchor?.minY ?? screen.visibleFrame.maxY
            let x = min(max(iconMidX - size.width / 2, sf.minX), sf.maxX - size.width)
            panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height),
                           display: false)
            model.anchorX = iconMidX - x
        case .bottomCenter:
            guard let screen = NSScreen.main ?? screen else { return }
            let vf = screen.visibleFrame
            let y = vf.minY + Self.bottomLift - Self.bottomInset
            panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: y, width: size.width, height: size.height),
                           display: false)
            model.anchorX = nil
        }
    }
}
