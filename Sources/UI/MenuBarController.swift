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

    /// Redraws the icon while it animates (level bars, shimmer, loading ring, pop).
    private var frameTimer: Timer?
    private var popStarted: Date?
    private var appearanceObservation: NSKeyValueObservation?
    private var menuBarIsDark: Bool?
    /// What the static icon was last drawn as; animated frames always redraw.
    private var lastStaticKey: String?

    init(viewModel: PopoverViewModel) {
        self.viewModel = viewModel
        statusItem = NSStatusBar.system.statusItem(withLength: StatusItemView.width(for: .ready))
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(vm: viewModel))

        if let btn = statusItem.button {
            btn.target = self
            btn.action = #selector(togglePopover(_:))
            btn.imagePosition = .imageOnly
            // Coloured states are drawn for the menu bar's own light or dark look.
            // Setting the image itself re-fires this KVO, so redraw only on a real
            // light/dark change, or it loops at full CPU.
            appearanceObservation = btn.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self, let btn = self.statusItem.button else { return }
                    let dark = btn.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    if dark != self.menuBarIsDark { self.redraw() }
                }
            }
        }
        redraw()

        // The menu bar draws a status item from its button's image (views laid
        // over the button don't reach the screen on recent macOS), so every state
        // is rendered into that image.
        status.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.stateChanged() }
            .store(in: &cancellables)
        status.$insertPulse
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !DS.reduceMotion else { return }
                self.popStarted = Date()
                self.stateChanged()
            }
            .store(in: &cancellables)
    }

    private func stateChanged() {
        let width = StatusItemView.width(for: status.iconState)
        if statusItem.length != width { statusItem.length = width }
        statusItem.button?.setAccessibilityLabel(status.iconDescription)
        redraw()
        // Listening follows the microphone at the frame rate (not each level update,
        // which came at 120 a second); Reduce Motion doesn't hide the level.
        let animating = status.iconState == .listening
            || ((status.iconState == .transcribing || status.iconState == .loading) && !DS.reduceMotion)
        if animating || popStarted != nil {
            if frameTimer == nil {
                frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
            }
        } else {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    private func tick() {
        if let p = popStarted, Date().timeIntervalSince(p) > StatusItemView.popDuration { popStarted = nil }
        redraw()
        if popStarted == nil, ![.listening, .transcribing, .loading].contains(status.iconState) {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    private func redraw() {
        guard let btn = statusItem.button else { return }
        let state = status.iconState
        let dark = btn.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        menuBarIsDark = dark
        let animated = popStarted != nil || state == .listening || state == .transcribing || state == .loading
        let key = "\(state)-\(dark)"
        if !animated, key == lastStaticKey { return }
        lastStaticKey = animated ? nil : key
        let view = StatusItemView(
            state: state,
            levels: HUDAmplitudeModel.shared.samples,
            time: Date().timeIntervalSinceReferenceDate,
            pop: popStarted.map { Date().timeIntervalSince($0) } ?? nil)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = btn.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        // Plain glyph: let the system tint it for the menu bar like any other icon.
        image.isTemplate = state == .ready && popStarted == nil
        btn.image = image
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

/// The menu bar icon and its states (concept `.mbitem`): red tally with live level
/// bars while listening, grey with shimmering bars while transcribing, a badge
/// when setup is needed or the last dictation failed, dimmed with a ring while
/// the model loads, and a short pop after a successful insert.
struct StatusItemView: View {
    let state: AppStatus.IconState
    let levels: [CGFloat]
    /// Clock for the shimmer and the loading ring.
    let time: TimeInterval
    /// Seconds since the insert pop started, nil when not popping.
    let pop: TimeInterval?

    static let popDuration: TimeInterval = 0.45
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

    private var showsBars: Bool { state == .listening || state == .transcribing }

    /// Quick overshoot to 1.25 and back (the concept's pop after an insert).
    private var popScale: CGFloat {
        guard let pop else { return 1 }
        let x = min(max(pop / Self.popDuration, 0), 1)
        return 1 + 0.25 * CGFloat(sin(x * .pi))
    }

    var body: some View {
        HStack(spacing: Self.gap) {
            glyph
            if showsBars {
                LevelBars(levels: barLevels, shimmer: state == .transcribing, time: time)
                    .frame(width: Self.barsWidth, height: 14)
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(width: Self.width(for: state), height: 22)
        .foregroundStyle(state == .listening ? Color.white : Color.primary)
        .background(background)
    }

    private var glyph: some View {
        radioIcon
            .frame(width: Self.glyphWidth, height: Self.glyphHeight)
            .opacity(state == .loading ? 0.4 : 1)
            .scaleEffect(popScale)
            .overlay(alignment: .topTrailing) { badge }
            .overlay { if state == .loading { LoadingRing(time: time) } }
    }

    @ViewBuilder private var badge: some View {
        let color: Color? = switch state {
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
        }
    }

    @ViewBuilder private var background: some View {
        switch state {
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
        (0..<4).map { i in
            let idx = levels.count - 1 - i * 2
            return idx >= 0 ? levels[idx] : 0
        }
    }
}

private struct LevelBars: View {
    let levels: [CGFloat]
    let shimmer: Bool
    let time: TimeInterval

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.25)
                    .frame(width: 2.5, height: 3 + 11 * CGFloat(value(i)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func value(_ i: Int) -> Double {
        guard shimmer else { return Double(levels[i]) }
        if DS.reduceMotion { return 0.4 }
        // ease-in-out wave, 1 s period, 0.15 s apart (concept @keyframes shimmer)
        let phase = (time - Double(i) * 0.15).truncatingRemainder(dividingBy: 1)
        return 0.25 + 0.5 * (0.5 - 0.5 * cos(phase * 2 * .pi))
    }
}

/// Spinning arc around the dimmed glyph while the model loads.
private struct LoadingRing: View {
    let time: TimeInterval

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .rotationEffect(.degrees(DS.reduceMotion ? 0 : time.truncatingRemainder(dividingBy: 1) * 360))
            .frame(width: 18, height: 18)
    }
}
