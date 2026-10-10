import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid

public struct Permissions: Equatable {
    public let microphone: Bool
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let documentsAccess: Bool
    public var allGranted: Bool { microphone && accessibility && inputMonitoring }
    public init(microphone: Bool, accessibility: Bool, inputMonitoring: Bool, documentsAccess: Bool) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.documentsAccess = documentsAccess
    }
}

public final class PermissionsManager: Sendable {
    public static let shared = PermissionsManager()
    private init() {}

    public func current() -> Permissions {
        Permissions(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
            documentsAccess: checkDocumentsAccessPassively()
        )
    }

    public func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
    }

    public func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }

    public func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public func openInputMonitoringSettings() {
        // Asking first puts the app into the Input Monitoring list; without it the
        // user has to add it with "+" by hand.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    /// Best-effort passive check — avoids triggering the TCC prompt. We rely
    /// on `access()` which returns EPERM if TCC has blocked the directory.
    private func checkDocumentsAccessPassively() -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return access(docs.path, R_OK) == 0
    }
}
