import SwiftUI
import AppKit

/// Every size, colour and type style the UI uses, named by role (concept page,
/// "Правила, по которым это собрано"). Change a value here, never inline.
enum DS {
    // MARK: - Spacing (4-pt steps)

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20

    // MARK: - Shapes

    /// One row of a grouped settings section.
    static let rowHeight: CGFloat = 38
    /// The menu bar popover.
    static let popoverWidth: CGFloat = 340
    /// HUD capsule: one line / two lines (title + detail).
    static let hudHeight: CGFloat = 40
    static let hudTallHeight: CGFloat = 52
    /// HUD corners on macOS 14–15, where the HUD is a rounded rect, not a capsule.
    static let hudRadiusClassic: CGFloat = 12
    /// Popover list rows and cards.
    static let rowRadius: CGFloat = 9
    static let cardRadius: CGFloat = 12
    static let alertRadius: CGFloat = 12

    static var isGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    // MARK: - Type (macOS text styles)

    /// Onboarding title.
    static let title = Font.system(size: 22, weight: .bold)
    /// Section / pane title.
    static let headline = Font.system(size: 15, weight: .bold)
    /// Body text, rows, buttons.
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    /// Captions under rows, status lines.
    static let callout = Font.system(size: 11.5)
    static let calloutStrong = Font.system(size: 11.5, weight: .semibold)
    /// Times and counters: always tabular digits.
    static let caption = Font.system(size: 11).monospacedDigit()

    // MARK: - Colour (system roles only; the app's own colour is the red tally)

    /// Recording: menu bar icon, HUD dot.
    static let tally = Color(nsColor: .systemRed)
    /// Needs setup: badge, alert.
    static let warn = Color(nsColor: .systemOrange)
    /// Ready, inserted.
    static let ok = Color(nsColor: .systemGreen)

    // MARK: - Motion

    /// HUD drop/rise. Reduce Motion replaces it with a plain fade.
    static let hudSpring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Status pill colours offered in Settings → General → Appearance (concept `PILLS`).
enum PillColor: String, CaseIterable, Identifiable {
    case glass, black, graphite, blue, purple, pink, red, orange, green
    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    /// nil for glass: the system material.
    var fill: Color? {
        switch self {
        case .glass:    return nil
        case .black:    return Color(hex: 0x141418)
        case .graphite: return Color(hex: 0x5b5b63)
        case .blue:     return Color(hex: 0x0a6cff)
        case .purple:   return Color(hex: 0x7d4cdb)
        case .pink:     return Color(hex: 0xd63c8a)
        case .red:      return Color(hex: 0xd9342b)
        case .orange:   return Color(hex: 0xe07a10)
        case .green:    return Color(hex: 0x1f9d55)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

/// NSVisualEffectView backing for macOS 14–15 surfaces.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

extension View {
    /// Liquid Glass on macOS 26+, the system material elsewhere.
    @ViewBuilder
    func dsGlass<S: Shape>(_ shape: S, classic: some Shape = RoundedRectangle(cornerRadius: DS.hudRadiusClassic)) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(VisualEffectBackground(material: .popover).clipShape(classic))
                .overlay(classic.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }

    /// Primary action: prominent glass on macOS 26+, the blue bordered button elsewhere.
    @ViewBuilder
    func dsProminent() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Ordinary push button: glass on macOS 26+, bordered elsewhere.
    @ViewBuilder
    func dsButton() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

enum Announce {
    /// Tells VoiceOver about a state change ("Listening", errors).
    static func say(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
