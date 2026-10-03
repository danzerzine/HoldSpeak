import ApplicationServices
import CoreGraphics

public enum InsertionResult { case inserted, skippedSecureField, noFocus }

public enum TextInserter {
    public static func insert(_ text: String) -> InsertionResult {
        guard !text.isEmpty else { return .noFocus }
        let target = focusedTarget()
        guard target == .inserted else { return target }
        type(text)
        return .inserted
    }

    /// Whether there is a focused element that may receive typed text.
    public static func focusedTarget() -> InsertionResult {
        let systemElement = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let status = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let focusedObj = focused else { return .noFocus }
        let focusedElement = focusedObj as! AXUIElement

        var role: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &role)
        if let roleStr = role as? String, roleStr == "AXSecureTextField" {
            return .skippedSecureField
        }
        return .inserted
    }

    /// Types `text` into whatever has focus, without checking it.
    public static func type(_ text: String) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)
        post(virtualKey: 0) { event in
            utf16.withUnsafeBufferPointer { buf in
                event.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
        }
    }

    public static func backspace(_ count: Int) {
        for _ in 0..<max(count, 0) { post(virtualKey: 51) { _ in } }
    }

    /// Clears modifier flags: while the hotkey (e.g. Right Option) is still held,
    /// live-typed characters would otherwise arrive as Option/⌘ shortcuts.
    private static func post(virtualKey: CGKeyCode, configure: (CGEvent) -> Void) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { continue }
            configure(event)
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}
