import AppKit
import Sparkle

/// In-app updates through Sparkle: the feed (`SUFeedURL`) is the appcast on the
/// GitHub Pages site, each update is EdDSA-signed by `scripts/release.sh`.
/// Sparkle downloads the DMG, checks the signature and the code signing identity,
/// replaces the app and relaunches it.
///
/// Speak! lives in the menu bar, so a scheduled check that finds an update doesn't
/// pop a window over the user's work: it shows the banner in the popover
/// ("gentle reminder"), and the banner's Install opens Sparkle's dialog.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()

    /// Version of a found update not installed yet; drives the popover banner.
    @Published private(set) var availableVersion: String?

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    func start() {
        controller.startUpdater()
    }

    /// User-initiated: Sparkle shows its window (update found, or up to date).
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        pttLog("update: found \(version)")
        Task { @MainActor in self.availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        pttLog("update: up to date")
        Task { @MainActor in self.availableVersion = nil }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        pttLog("update: \(error.localizedDescription)")
    }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled checks never open Sparkle's window on their own: the popover
    /// banner (set in `didFindValidUpdate`) is the reminder.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }
}
