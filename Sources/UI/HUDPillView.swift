import SwiftUI

@MainActor
final class HUDAmplitudeModel: ObservableObject {
    /// One bar per sample, ~1.5 s of history at `sampleStep`.
    static let sampleCount = 26
    private static let sampleStep: Double = 0.06

    /// Level history for the waveform, 0...1, oldest first.
    @Published private(set) var samples = [CGFloat](repeating: 0, count: sampleCount)
    /// How far (0...1 of one sample) the waveform has scrolled since the last
    /// sample, so it glides left instead of jumping.
    @Published private(set) var scroll: CGFloat = 0
    /// When the current recording started, for the elapsed time in the HUD.
    private(set) var startedAt = Date()

    static let shared = HUDAmplitudeModel()

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var sinceSample: Double = 0
    /// Light EMA of the normalised mic level; smooths buffer-to-buffer jitter.
    private var smoothed: Double = 0
    /// Fast attack, slower release: the waveform swells with a word and eases off.
    private var follower = LevelEnvelope(attack: 0.03, release: 0.12)

    private init() {}

    /// Runs the 60 Hz animation timer while listening. Starts from a flat line.
    func start() {
        startedAt = Date()
        guard timer == nil else { return }
        smoothed = 0
        sinceSample = 0
        scroll = 0
        follower.reset()
        samples = samples.map { _ in 0 }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let now = CACurrentMediaTime()
                self.tick(dt: min(now - self.lastTick, 0.1))
                self.lastTick = now
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func push(_ amp: Float) {
        smoothed += (LevelEnvelope.normalize(rms: amp) - smoothed) * 0.6
    }

    private func tick(dt: Double) {
        let value = CGFloat(follower.step(toward: smoothed, dt: dt))
        sinceSample += dt
        if sinceSample >= Self.sampleStep {
            sinceSample -= Self.sampleStep
            samples = Array(samples.dropFirst()) + [value]
        } else {
            samples[samples.count - 1] = value
        }
        scroll = CGFloat(sinceSample / Self.sampleStep)
    }
}

/// What the HUD shows. Success has no HUD state: the text in the field and the
/// icon's pop say it (Daniyar 04.10: «мне кажется лишний статус»).
enum HUDContent: Equatable {
    case listening
    case transcribing
    case message(HUDMessageKind, title: String, detail: String)

    var isTall: Bool { if case .message = self { return true } else { return false } }

    /// What VoiceOver says when the HUD switches to this.
    var announcement: String {
        switch self {
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .message(_, let title, let detail): return "\(title). \(detail)"
        }
    }
}

enum HUDMessageKind: Equatable { case warn, error, lock, loading }

@MainActor
final class HUDModel: ObservableObject {
    static let shared = HUDModel()
    @Published var content: HUDContent = .listening
    @Published var shown = false
    /// Where the pill's centre should be, in panel coordinates (under-icon mode).
    @Published var anchorX: CGFloat?
    @Published var position: HUDPosition = .underMenuBarIcon
    private init() {}
}

/// The panel's whole content: the pill placed under the icon or at the bottom,
/// dropping out of the icon (or rising) as it appears.
struct HUDView: View {
    @ObservedObject private var model = HUDModel.shared

    var body: some View {
        HUDPlacement(anchorX: model.anchorX, atTop: model.position == .underMenuBarIcon) {
            if model.shown {
                HUDPill(content: model.content)
                    .transition(transition)
            }
        }
        .animation(DS.reduceMotion ? .easeOut(duration: 0.15) : DS.hudSpring, value: model.shown)
        .animation(DS.reduceMotion ? nil : DS.hudSpring, value: model.content)
    }

    private var transition: AnyTransition {
        if DS.reduceMotion { return .opacity }
        return model.position == .underMenuBarIcon
            ? .modifier(active: HUDDrop(scaleX: 0.6, scaleY: 0.4, y: -14, anchor: .top, opacity: 0),
                        identity: HUDDrop(scaleX: 1, scaleY: 1, y: 0, anchor: .top, opacity: 1))
            : .modifier(active: HUDDrop(scaleX: 0.85, scaleY: 0.85, y: 14, anchor: .bottom, opacity: 0),
                        identity: HUDDrop(scaleX: 1, scaleY: 1, y: 0, anchor: .bottom, opacity: 1))
    }
}

private struct HUDDrop: ViewModifier {
    let scaleX: CGFloat, scaleY: CGFloat, y: CGFloat
    let anchor: UnitPoint
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: scaleX, y: scaleY, anchor: anchor)
            .offset(y: y)
            .opacity(opacity)
    }
}

/// Puts the single pill at the top (centred on the icon, kept 8 pt inside the
/// panel, which itself is kept on screen) or centred at the bottom.
private struct HUDPlacement: Layout {
    var anchorX: CGFloat?
    var atTop: Bool
    static let edgeInset: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            var cx = atTop ? (anchorX.map { bounds.minX + $0 } ?? bounds.midX) : bounds.midX
            let half = size.width / 2
            cx = min(max(cx, bounds.minX + half + Self.edgeInset), bounds.maxX - half - Self.edgeInset)
            let y = atTop ? bounds.minY + OverlayWindow.topInset : bounds.maxY - OverlayWindow.bottomInset - size.height
            view.place(at: CGPoint(x: cx - half, y: y), proposal: ProposedViewSize(size))
        }
    }
}

/// The capsule itself (concept `.hud`).
struct HUDPill: View {
    let content: HUDContent
    @ObservedObject private var prefs = PreferencesStore.shared

    private var color: PillColor { PillColor(rawValue: prefs.pillColor) ?? .glass }
    private var solid: Bool { color.fill != nil }
    private var primaryText: Color { solid ? .white : .primary }
    private var secondaryText: Color { solid ? .white.opacity(0.72) : .secondary }
    private var height: CGFloat { content.isTall ? DS.hudTallHeight : DS.hudHeight }

    var body: some View {
        HStack(spacing: 10) {
            switch content {
            case .listening:    listening
            case .transcribing: transcribing
            case .message(let kind, let title, let detail): message(kind, title, detail)
            }
        }
        .font(DS.body)
        .foregroundStyle(primaryText)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .frame(height: height)
        .fixedSize()
        .modifier(PillChrome(fill: color.fill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(content.announcement)
    }

    // MARK: States

    @ViewBuilder private var listening: some View {
        Circle()
            .fill(solid ? Color.white : DS.tally)
            .frame(width: 8, height: 8)
            .background(Circle().fill((solid ? Color.white.opacity(0.28) : DS.tally.opacity(0.22))).frame(width: 16, height: 16))
            .frame(width: 16)
        Text("Listening").fontWeight(.semibold)
        Waveform(color: primaryText)
            .frame(width: 96, height: 24)
        ElapsedMeta(limitMinutes: prefs.maxRecordingMinutes, secondary: secondaryText)
        if let lang = prefs.primaryLanguage.whisperCode {
            Text(lang.uppercased())
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(secondaryText)
        }
    }

    @ViewBuilder private var transcribing: some View {
        Spinner(primary: primaryText, track: solid ? .white.opacity(0.4) : Color.primary.opacity(0.3))
        Text("Transcribing").fontWeight(.semibold)
        Text(EngineText.short(prefs))
            .font(.system(size: 12))
            .foregroundStyle(secondaryText)
    }

    @ViewBuilder private func message(_ kind: HUDMessageKind, _ title: String, _ detail: String) -> some View {
        Group {
            switch kind {
            case .warn:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.warn)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(solid ? .white : DS.tally)
            case .lock:
                Image(systemName: "lock.fill").foregroundStyle(secondaryText)
            case .loading:
                Spinner(primary: primaryText, track: solid ? .white.opacity(0.4) : Color.primary.opacity(0.3))
            }
        }
        .font(.system(size: 14))
        .frame(width: 16)
        VStack(alignment: .leading, spacing: 1) {
            Text(title).fontWeight(.semibold)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(secondaryText)
        }
        .lineLimit(1)
    }

}

/// Solid colour with a hairline and a soft shadow, or the system glass.
private struct PillChrome: ViewModifier {
    let fill: Color?

    private var shape: AnyShape {
        DS.isGlass ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: DS.hudRadiusClassic))
    }

    func body(content: Content) -> some View {
        if let fill {
            content.background {
                shape
                    .fill(fill)
                    .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
            }
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background {
                VisualEffectBackground(material: .popover)
                    .clipShape(shape)
                    .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.22), radius: 25, y: 18)
            }
        }
    }
}

/// "0:03" while recording; "Stops in 0:28" in orange for the last 30 s before the limit.
private struct ElapsedMeta: View {
    let limitMinutes: Int
    let secondary: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let elapsed = Int(ctx.date.timeIntervalSince(HUDAmplitudeModel.shared.startedAt))
            let remaining = limitMinutes * 60 - elapsed
            if limitMinutes > 0, remaining <= 30 {
                Text("Stops in \(Self.clock(max(0, remaining)))").foregroundStyle(DS.warn)
            } else {
                Text(Self.clock(elapsed)).foregroundStyle(secondary)
            }
        }
        .font(.system(size: 12).monospacedDigit())
    }

    static func clock(_ s: Int) -> String { "\(s / 60):" + String(format: "%02d", s % 60) }
}

/// Level bars, newest at the right, older ones fading out (concept canvas: 24 bars,
/// 2.5 pt wide, 4 pt pitch).
private struct Waveform: View {
    let color: Color
    @ObservedObject private var model = HUDAmplitudeModel.shared

    var body: some View {
        Canvas { ctx, size in
            let bars = Array(model.samples.suffix(24))
            let pitch: CGFloat = 4
            for (i, v) in bars.enumerated() {
                let x = CGFloat(i) * pitch - model.scroll * pitch
                guard x >= -2.5 else { continue }
                let h = max(2, v * 22)
                let rect = CGRect(x: x, y: size.height / 2 - h / 2, width: 2.5, height: h)
                ctx.opacity = 0.25 + 0.75 * Double(i) / Double(bars.count - 1)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.25), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// 14 pt ring with a bright quarter, 0.8 s per turn (concept `.spin`).
private struct Spinner: View {
    let primary: Color
    let track: Color

    var body: some View {
        TimelineView(.animation(paused: DS.reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(track, lineWidth: 2)
                Circle().trim(from: 0, to: 0.25).stroke(primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 0.8) / 0.8 * 360))
            }
        }
        .frame(width: 14, height: 14)
    }
}
