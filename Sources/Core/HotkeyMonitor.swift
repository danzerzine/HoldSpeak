import Cocoa
import Combine

public final class HotkeyMonitor {
    /// `.startHold` fires immediately on key press so recording can begin without
    /// losing the first syllables. If the key is released before `holdThresholdMs`
    /// the press is treated as an accidental tap and `.cancelHold` follows instead
    /// of `.endHold`.
    public enum Event { case startHold; case endHold; case cancelHold }
    public let events = PassthroughSubject<Event, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdStartedAt: Date?

    private let prefs: PreferencesStore
    public init(prefs: PreferencesStore = .shared) { self.prefs = prefs }

    public func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let this = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if this.handle(event: event, type: type) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )
        guard let tap else {
            NSLog("HotkeyMonitor: failed to create event tap (missing Accessibility permission?)")
            return
        }
        self.eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        }
        eventTap = nil
        runLoopSource = nil
        holdStartedAt = nil
    }

    /// Returns true if the event should be consumed (dropped).
    private func handle(event: CGEvent, type: CGEventType) -> Bool {
        let binding = prefs.hotkey
        switch binding.kind {
        case .modifier:
            if type == .flagsChanged { handleModifier(event: event, binding: binding) }
            return false
        case .key:
            return handleKey(event: event, type: type, binding: binding)
        }
    }

    private func handleModifier(event: CGEvent, binding: HotkeyBinding) {
        let flags = event.flags.rawValue
        let ourKeyDown = (flags & binding.deviceBit) != 0
        let otherGeneralMods = flags & HotkeyBinding.allGeneralMods & ~binding.mods
        if ourKeyDown && otherGeneralMods != 0 { return }

        if ourKeyDown && holdStartedAt == nil {
            beginHold()
        } else if !ourKeyDown {
            endOrCancel()
        }
    }

    private func handleKey(event: CGEvent, type: CGEventType, binding: HotkeyBinding) -> Bool {
        guard type == .keyDown || type == .keyUp else { return false }
        let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard kc == binding.keyCode else { return false }
        let flags = event.flags.rawValue
        let currentMods = flags & HotkeyBinding.allGeneralMods
        if type == .keyDown {
            guard currentMods == binding.mods else { return false }
            if holdStartedAt == nil { beginHold() }
            return true
        } else {
            endOrCancel()
            return true
        }
    }

    private func beginHold() {
        holdStartedAt = Date()
        events.send(.startHold)
    }

    private func endOrCancel() {
        guard let startedAt = holdStartedAt else { return }
        holdStartedAt = nil
        let heldMs = Date().timeIntervalSince(startedAt) * 1000.0
        events.send(heldMs >= Double(prefs.holdThresholdMs) ? .endHold : .cancelHold)
    }
}
