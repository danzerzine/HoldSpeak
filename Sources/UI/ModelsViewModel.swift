import SwiftUI

@MainActor
@Observable
final class ModelsViewModel {
    var downloading = false
    var progress: Double = 0
    /// Disk used by models the app downloaded itself (not other apps' copies).
    var managedBytes: Int64 = 0
    /// Called on main after a successful download, so the engine can load the model.
    @ObservationIgnored var onDownloaded: ((WhisperModelID) -> Void)?
    /// Called on main after the downloaded models were deleted.
    @ObservationIgnored var onDeleted: (() -> Void)?

    /// Bumped when the disk changes behind `isLocated(_:)`; reading it there makes views re-evaluate.
    private(set) var locatedRevision = 0

    func isLocated(_ id: WhisperModelID) -> Bool {
        _ = locatedRevision
        return ModelManager.shared.locateModel(id) != nil
    }

    func status(for id: WhisperModelID) -> String {
        isLocated(id) ? "Downloaded" : "Not downloaded"
    }

    func download(_ id: WhisperModelID) async {
        downloading = true
        progress = 0
        defer { downloading = false }
        do {
            _ = try await ModelManager.shared.download(id) { [weak self] p in
                Task { @MainActor in self?.progress = p }
            }
            onDownloaded?(id)
        } catch {
            pttLog("Model download failed: \(error)")
        }
        refreshManagedSize()
    }

    func refreshManagedSize() {
        Task {
            managedBytes = await Task.detached(priority: .utility) { ModelManager.shared.managedBytes() }.value
        }
    }

    func deleteManagedModels() {
        do {
            try ModelManager.shared.deleteManagedModels()
            pttLog("Deleted downloaded Whisper models")
        } catch {
            pttLog("Deleting models failed: \(error)")
        }
        locatedRevision += 1 // isLocated(_:) answers differently now
        onDeleted?()
        refreshManagedSize()
    }
}
