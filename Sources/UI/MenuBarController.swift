import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController {
    let statusItem: NSStatusItem
    private let popover: NSPopover
    private let viewModel: PopoverViewModel
    private let status = AppStatus.shared
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: PopoverViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: StatusItemView.width(for: .ready))
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(vm: viewModel))

        if let btn = statusItem.button {
            btn.target = self
            btn.action = #selector(togglePopover(_:))
            // The icon is drawn by SwiftUI on top of the button; the button keeps
            // the clicks and the system highlight while the popover is open.
            let host = PassThroughHostingView(rootView: StatusItemView())
            host.translatesAutoresizingMaskIntoConstraints = false
            btn.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: btn.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: btn.trailingAnchor),
                host.topAnchor.constraint(equalTo: btn.topAnchor),
                host.bottomAnchor.constraint(equalTo: btn.bottomAnchor),
            ])
            btn.setAccessibilityLabel(status.iconDescription)
        }

        // The item widens to make room for the level bars while recording.
        status.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                let width = StatusItemView.width(for: self.status.iconState)
                if self.statusItem.length != width {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = DS.reduceMotion ? 0 : 0.3
                        self.statusItem.length = width
                    }
                }
                self.statusItem.button?.setAccessibilityLabel(self.status.iconDescription)
            }
            .store(in: &cancellables)
    }

    var statusItemFrame: CGRect? {
        guard let win = statusItem.button?.window, let btn = statusItem.button else { return nil }
        return win.convertToScreen(btn.convert(btn.bounds, to: nil))
    }

    var statusItemScreen: NSScreen? { statusItem.button?.window?.screen }

    /// Closes the popover and hands focus back to the app the user was in.
    func closePopoverAndReturnFocus() {
        if popover.isShown { popover.performClose(nil) }
        NSApp.hide(nil)
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            viewModel.refresh()
            status.refreshPermissions()
            // Seen: the error badge has done its job.
            status.lastDictationFailed = false
            popover.appearance = PreferencesStore.shared.appTheme.nsAppearance
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// Lets clicks fall through to the status bar button underneath.
private final class PassThroughHostingView<V: View>: NSHostingView<V> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The menu bar icon and its states (concept `.mbitem`): red tally with live level
/// bars while listening, grey with shimmering bars while transcribing, a badge
/// when setup is needed or the last dictation failed, dimmed with a ring while
/// the model loads, and a short pop after a successful insert.
struct StatusItemView: View {
    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var level = HUDAmplitudeModel.shared
    @State private var pop = false

    static let glyphHeight: CGFloat = 17
    static var glyphWidth: CGFloat {
        guard let img = BundledIcon.radio, img.size.height > 0 else { return 16 }
        return (glyphHeight * img.size.width / img.size.height).rounded()
    }
    private static let padding: CGFloat = 7
    private static let barsWidth: CGFloat = 20
    private static let gap: CGFloat = 6

    static func width(for state: AppStatus.IconState) -> CGFloat {
        let base = glyphWidth + padding * 2
        switch state {
        case .listening, .transcribing: return base + gap + barsWidth
        default: return base
        }
    }

    private var showsBars: Bool {
        status.iconState == .listening || status.iconState == .transcribing
    }

    var body: some View {
        HStack(spacing: Self.gap) {
            glyph
            if showsBars {
                LevelBars(levels: barLevels, shimmer: status.iconState == .transcribing)
                    .frame(width: Self.barsWidth, height: 14)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(height: 22)
        .foregroundStyle(status.iconState == .listening ? Color.white : Color.primary)
        .background(background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.reduceMotion ? nil : .easeOut(duration: 0.2), value: status.iconState)
        .onChange(of: status.insertPulse) {
            guard !DS.reduceMotion else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
            }
        }
    }

    private var glyph: some View {
        radioIcon
            .frame(width: Self.glyphWidth, height: Self.glyphHeight)
            .opacity(status.iconState == .loading ? 0.4 : 1)
            .scaleEffect(pop ? 1.25 : 1)
            .overlay(alignment: .topTrailing) { badge }
            .overlay { if status.iconState == .loading { LoadingRing() } }
    }

    @ViewBuilder private var badge: some View {
        let color: Color? = switch status.iconState {
        case .attention: DS.warn
        case .error:     DS.tally
        default:         nil
        }
        if let color {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.75))
                .offset(x: 3, y: -1)
                .transition(.scale)
        }
    }

    @ViewBuilder private var background: some View {
        switch status.iconState {
        case .listening:
            RoundedRectangle(cornerRadius: 6).fill(DS.tally.opacity(0.92))
        case .transcribing:
            RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.26))
        default:
            Color.clear
        }
    }

    /// Four bars from the newest level samples (concept: every other sample).
    private var barLevels: [CGFloat] {
        let s = level.samples
        return (0..<4).map { i in
            let idx = s.count - 1 - i * 2
            return idx >= 0 ? s[idx] : 0
        }
    }
}

private struct LevelBars: View {
    let levels: [CGFloat]
    let shimmer: Bool

    var body: some View {
        if shimmer && !DS.reduceMotion {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                bars { i in
                    // ease-in-out wave, 1 s period, 0.15 s apart (concept @keyframes shimmer)
                    let phase = (t - Double(i) * 0.15).truncatingRemainder(dividingBy: 1)
                    return 0.25 + 0.5 * (0.5 - 0.5 * cos(phase * 2 * .pi))
                }
            }
        } else {
            bars { i in shimmer ? 0.4 : levels[i] }
        }
    }

    private func bars(_ value: @escaping (Int) -> Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.25)
                    .frame(width: 2.5, height: 3 + 11 * CGFloat(value(i)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Spinning arc around the dimmed glyph while the model loads.
private struct LoadingRing: View {
    var body: some View {
        TimelineView(.animation(paused: DS.reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
                .frame(width: 18, height: 18)
        }
    }
}
