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
    /// The binding whose press started the current hold; only its release ends it.
    private var holdBinding: HotkeyBinding?
    /// Copy of the keyDown a `.key` hold swallowed; re-posted if the press turns out to be a tap.
    private var swallowedKeyDown: CGEvent?

    /// Marks events this monitor re-posts so the tap lets them through.
    private static let repostMarker: Int64 = 0x48534B /* "HSK" */
    /// Tests swap this out so they never type into the real session.
    var repost: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }

    /// Set while Preferences is capturing a new binding: events pass through
    /// untouched so pressing the current hotkey doesn't start a dictation and
    /// still reaches the recorder. Main thread only (the tap runs on the main run loop).
    public static var isPaused = false

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
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // macOS disables the tap if the main thread stalls; without this
                    // the hotkey stays dead until relaunch.
                    pttLog("HotkeyMonitor: event tap disabled (\(type.rawValue)) — re-enabling")
                    if let tap = this.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if this.handle(event: event, type: type) {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )
        guard let tap else {
            pttLog("HotkeyMonitor: failed to create event tap (missing Accessibility permission?)")
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
        resetHold()
    }

    /// Returns true if the event should be consumed (dropped).
    private func handle(event: CGEvent, type: CGEventType) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.repostMarker { return false }
        if Self.isPaused {
            // A hold in progress when capture began would never see its release.
            cancelHold()
            return false
        }
        if let active = holdBinding { return handle(event: event, type: type, binding: active) }
        for binding in prefs.activeHotkeys {
            let consumed = handle(event: event, type: type, binding: binding)
            if consumed || holdBinding != nil { return consumed }
        }
        return false
    }

    func handle(event: CGEvent, type: CGEventType, binding: HotkeyBinding) -> Bool {
        switch binding.kind {
        case .modifier:
            if type == .flagsChanged {
                handleModifier(event: event, binding: binding)
            } else if type == .keyDown && holdBinding == binding {
                // ⌥+letter, ⌘C and the like: the modifier is part of a shortcut, not a dictation.
                cancelHold()
            }
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
            beginHold(binding)
        } else if !ourKeyDown && holdBinding == binding {
            endOrCancel()
        }
    }

    func handleKey(event: CGEvent, type: CGEventType, binding: HotkeyBinding) -> Bool {
        guard type == .keyDown || type == .keyUp else { return false }
        let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard kc == binding.keyCode else { return false }
        let flags = event.flags.rawValue
        let currentMods = flags & HotkeyBinding.allGeneralMods
        if type == .keyDown {
            guard currentMods == binding.mods else { return false }
            if holdStartedAt == nil {
                beginHold(binding)
                swallowedKeyDown = event.copy()
            }
            return true
        } else {
            // Only swallow the keyUp that ends our hold — e.g. with ⌥Space bound, a
            // plain Space keyUp must still reach the focused app.
            guard holdBinding == binding else { return false }
            let keyDown = swallowedKeyDown
            if !endOrCancel(), let keyDown, let keyUp = event.copy() {
                // A tap: give the focused app the keystroke it would have got without us.
                for e in [keyDown, keyUp] {
                    e.setIntegerValueField(.eventSourceUserData, value: Self.repostMarker)
                    repost(e)
                }
            }
            return true
        }
    }

    private func beginHold(_ binding: HotkeyBinding) {
        holdStartedAt = Date()
        holdBinding = binding
        events.send(.startHold)
    }

    /// Returns true if the hold was long enough to count as a dictation.
    @discardableResult
    private func endOrCancel() -> Bool {
        guard let startedAt = holdStartedAt else { return false }
        resetHold()
        let heldMs = Date().timeIntervalSince(startedAt) * 1000.0
        let long = heldMs >= Double(prefs.holdThresholdMs)
        events.send(long ? .endHold : .cancelHold)
        return long
    }

    private func cancelHold() {
        guard holdStartedAt != nil else { return }
        resetHold()
        events.send(.cancelHold)
    }

    private func resetHold() {
        holdStartedAt = nil
        holdBinding = nil
        swallowedKeyDown = nil
    }
}
