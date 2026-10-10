import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The one shortcut recorder listening for keys. Two recorders sit side by side in
/// Settings: starting one stops the other, and only the owner unpauses the hotkey.
@MainActor
@Observable
final class HotkeyCapture {
    static let shared = HotkeyCapture()
    /// Which hotkey is being recorded: false the first, true the second, nil none.
    private(set) var target: Bool?
    @ObservationIgnored private var monitor: Any?

    func start(second: Bool, handler: @escaping (NSEvent) -> NSEvent?) {
        stop()
        target = second
        HotkeyMonitor.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handler)
    }

    /// Stops the recorder for `second`; a call from a recorder that doesn't own the capture does nothing.
    func stop(second: Bool) {
        guard target == second else { return }
        stop()
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        guard target != nil else { return }
        target = nil
        HotkeyMonitor.isPaused = false
    }
}

struct HotkeyRecorderView: View {
    @ObservedObject var prefs = PreferencesStore.shared
    private let capture = HotkeyCapture.shared
    /// Edits the second hotkey instead of the first.
    var second = false
    private var recording: Bool { capture.target == second }
    @State private var previousDeviceBits: UInt64 = 0
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.s1) {
            Button(action: toggle) {
                // Form greys LabeledContent values; the keycap stays primary
                // and on one line.
                Text(recording ? "Press a key…" : EngineText.keycap(binding))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 110)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.14),
                                      lineWidth: recording ? 2 : 0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(recording ? "Press the new key, or Esc to cancel" : "Click and press a new key")
            .accessibilityLabel(recording ? "Recording a shortcut" : "Shortcut \(binding.label). Click to change")
            if rejected {
                // A bare letter would stop typing system-wide.
                Text("Add ⌃, ⌥ or ⌘ to that key, or use an F-key or a single modifier.")
                    .font(DS.callout)
                    .foregroundStyle(DS.warn)
            }
        }
        .onDisappear { stop() }
    }

    private var binding: HotkeyBinding {
        get { second ? prefs.hotkey2 : prefs.hotkey }
        nonmutating set { if second { prefs.hotkey2 = newValue } else { prefs.hotkey = newValue } }
    }

    private func toggle() {
        if recording { stop() } else { start() }
    }

    private func start() {
        rejected = false
        previousDeviceBits = UInt64(NSEvent.modifierFlags.rawValue) & 0xFFFF
        capture.start(second: second) { event in
            if let b = bindingFrom(event) {
                binding = b
                stop()
                return nil
            }
            // Swallow keys while recording so they don't reach other controls.
            return nil
        }
    }

    private func stop() {
        capture.stop(second: second)
    }

    private static func isFunctionKey(_ kc: UInt16) -> Bool {
        [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            .contains(Int(kc))
    }

    private func bindingFrom(_ event: NSEvent) -> HotkeyBinding? {
        guard let cg = event.cgEvent else { return nil }
        let flags = cg.flags.rawValue
        if event.type == .keyDown {
            // Escape alone cancels.
            if Int(event.keyCode) == kVK_Escape && (flags & HotkeyBinding.allGeneralMods) == 0 {
                stop()
                return nil
            }
            let mods = flags & HotkeyBinding.allGeneralMods
            // Shift alone doesn't count: ⇧A still types a letter.
            guard mods & ~0x00020000 != 0 || Self.isFunctionKey(event.keyCode) else {
                rejected = true
                return nil
            }
            rejected = false
            return .key(keyCode: event.keyCode, mods: mods)
        } else {
            let current = flags & 0xFFFF
            let newBits = current & ~previousDeviceBits
            previousDeviceBits = current
            guard newBits != 0 else { return nil }
            // Pick lowest single bit.
            let bit = newBits & (~newBits + 1)
            return HotkeyBinding.modifier(deviceBit: bit)
        }
    }
}
