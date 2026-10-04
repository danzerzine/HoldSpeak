import XCTest
import Combine
import Carbon.HIToolbox
@testable import HoldSpeakCore

final class HotkeyMonitorTests: XCTestCase {
    private let optSpace = HotkeyBinding.key(keyCode: UInt16(kVK_Space), mods: 0x00080000)

    /// Builds (never posts) a keyboard event for feeding `handleKey` directly.
    private func key(_ code: Int, down: Bool, flags: CGEventFlags = []) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
        e.flags = flags
        return e
    }

    private var reposted: [CGEvent] = []

    private func makeMonitor() -> HotkeyMonitor {
        let m = HotkeyMonitor()
        m.repost = { [unowned self] in self.reposted.append($0) }
        return m
    }

    private let rightOption = HotkeyBinding.rightOption

    /// A flagsChanged event as Right Option produces it (device bit + general ⌥ bit).
    private func flags(_ raw: UInt64) -> CGEvent {
        let e = CGEvent(source: nil)!
        e.type = .flagsChanged
        e.flags = CGEventFlags(rawValue: raw)
        return e
    }

    func test_modifierHold_cancelledByKeyPressDuringHold() {
        let monitor = makeMonitor()
        var events: [HotkeyMonitor.Event] = []
        let sub = monitor.events.sink { events.append($0) }
        defer { sub.cancel() }

        _ = monitor.handle(event: flags(0x00080000 | 0x40), type: .flagsChanged, binding: rightOption)
        XCTAssertEqual(events, [.startHold])
        // ⌥+letter while held: a shortcut, not dictation.
        XCTAssertFalse(monitor.handle(event: key(kVK_ANSI_A, down: true, flags: .maskAlternate),
                                      type: .keyDown, binding: rightOption))
        XCTAssertEqual(events, [.startHold, .cancelHold])
        // Releasing afterwards sends nothing more.
        _ = monitor.handle(event: flags(0), type: .flagsChanged, binding: rightOption)
        XCTAssertEqual(events.count, 2)
    }

    func test_modifierHold_ignoredWhenCombinedWithAnotherModifier() {
        let monitor = makeMonitor()
        var events: [HotkeyMonitor.Event] = []
        let sub = monitor.events.sink { events.append($0) }
        defer { sub.cancel() }

        _ = monitor.handle(event: flags(0x00080000 | 0x40 | 0x00100000 | 0x08), type: .flagsChanged,
                           binding: rightOption)
        XCTAssertTrue(events.isEmpty)
    }

    func test_keyTap_isRepostedToTheFocusedApp() {
        let monitor = makeMonitor()
        _ = monitor.handleKey(event: key(kVK_Space, down: true, flags: .maskAlternate), type: .keyDown, binding: optSpace)
        _ = monitor.handleKey(event: key(kVK_Space, down: false, flags: .maskAlternate), type: .keyUp, binding: optSpace)
        XCTAssertEqual(reposted.map { $0.type }, [.keyDown, .keyUp])
    }

    func test_plainKeyUp_passesThroughWhenNoHoldActive() {
        let monitor = makeMonitor()
        XCTAssertFalse(monitor.handleKey(event: key(kVK_Space, down: true), type: .keyDown, binding: optSpace))
        XCTAssertFalse(monitor.handleKey(event: key(kVK_Space, down: false), type: .keyUp, binding: optSpace))
    }

    func test_boundKeyUp_isConsumedAndEndsHold() {
        let monitor = makeMonitor()
        var events: [HotkeyMonitor.Event] = []
        let sub = monitor.events.sink { events.append($0) }
        defer { sub.cancel() }

        XCTAssertTrue(monitor.handleKey(event: key(kVK_Space, down: true, flags: .maskAlternate),
                                        type: .keyDown, binding: optSpace))
        XCTAssertTrue(monitor.handleKey(event: key(kVK_Space, down: false, flags: .maskAlternate),
                                        type: .keyUp, binding: optSpace))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .startHold)

        // A second keyUp with the hold already over must pass through.
        XCTAssertFalse(monitor.handleKey(event: key(kVK_Space, down: false), type: .keyUp, binding: optSpace))
    }

    func test_secondBindingRelease_doesNotEndFirstBindingsHold() {
        let monitor = makeMonitor()
        let f13 = HotkeyBinding.key(keyCode: UInt16(kVK_F13), mods: 0)
        var events: [HotkeyMonitor.Event] = []
        let sub = monitor.events.sink { events.append($0) }
        defer { sub.cancel() }

        XCTAssertTrue(monitor.handleKey(event: key(kVK_Space, down: true, flags: .maskAlternate),
                                        type: .keyDown, binding: optSpace))
        XCTAssertFalse(monitor.handleKey(event: key(kVK_F13, down: false), type: .keyUp, binding: f13))
        XCTAssertEqual(events, [.startHold])
        XCTAssertTrue(monitor.handleKey(event: key(kVK_Space, down: false, flags: .maskAlternate),
                                        type: .keyUp, binding: optSpace))
        XCTAssertEqual(events.count, 2)
    }

    func test_otherKeys_areIgnored() {
        let monitor = makeMonitor()
        XCTAssertFalse(monitor.handleKey(event: key(kVK_ANSI_A, down: true, flags: .maskAlternate),
                                         type: .keyDown, binding: optSpace))
    }

    func test_modifierHold_cancelledByMouseClick() {
        let monitor = makeMonitor()
        var events: [HotkeyMonitor.Event] = []
        let sub = monitor.events.sink { events.append($0) }
        defer { sub.cancel() }

        _ = monitor.handle(event: flags(0x00080000 | 0x40), type: .flagsChanged, binding: rightOption)
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: .zero, mouseButton: .left)!
        XCTAssertFalse(monitor.handle(event: click, type: .leftMouseDown, binding: rightOption))
        XCTAssertEqual(events, [.startHold, .cancelHold])
    }

    func test_modifierHold_notCancelledByOwnTypedText() {
        let monitor = makeMonitor()
        var events: [HotkeyMonitor.Event] = []
        let sub = monitor.events.sink { events.append($0) }
        defer { sub.cancel() }

        _ = monitor.handle(event: flags(0x00080000 | 0x40), type: .flagsChanged, binding: rightOption)
        // TextInserter types the previous dictation while this one is held.
        let typed = key(0, down: true, flags: .maskAlternate)
        typed.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.repostMarker)
        XCTAssertFalse(monitor.handle(event: typed, type: .keyDown))
        XCTAssertEqual(events, [.startHold])
    }
}

final class TextInserterTests: XCTestCase {
    func test_passwordFieldDetectedBySubrole() {
        // What a real NSSecureTextField reports through AX (checked 04.10).
        XCTAssertTrue(TextInserter.isSecureField(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertFalse(TextInserter.isSecureField(role: "AXTextField", subrole: nil))
        XCTAssertFalse(TextInserter.isSecureField(role: "AXTextArea", subrole: nil))
    }
}
