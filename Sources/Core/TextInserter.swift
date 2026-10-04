import ApplicationServices
import CoreGraphics

public enum InsertionResult { case inserted, skippedSecureField, noFocus }

public enum TextInserter {
    public static func insert(_ text: String) -> InsertionResult {
        guard !text.isEmpty else { return .noFocus }

        let systemElement = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let status = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard status == .success, let focusedObj = focused else { return .noFocus }
        let focusedElement = focusedObj as! AXUIElement

        var role: AnyObject?
        var subrole: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(focusedElement, kAXSubroleAttribute as CFString, &subrole)
        if isSecureField(role: role as? String, subrole: subrole as? String) {
            return .skippedSecureField
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buf in
            down?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            up?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        // Marked so our own hotkey tap doesn't take the typing for a shortcut and
        // cancel a dictation the user has already started holding.
        for e in [down, up] { e?.setIntegerValueField(.eventSourceUserData, value: HotkeyMonitor.repostMarker) }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return .inserted
    }

    /// A password field is a text field with the secure subrole (role AXTextField,
    /// subrole AXSecureTextField); there is no AXSecureTextField role.
    static func isSecureField(role: String?, subrole: String?) -> Bool {
        subrole == kAXSecureTextFieldSubrole as String || role == kAXSecureTextFieldSubrole as String
    }
}
