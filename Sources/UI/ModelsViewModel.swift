import SwiftUI

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published var downloading = false
    @Published var progress: Double = 0
    /// Disk used by models the app downloaded itself (not other apps' copies).
    @Published var managedBytes: Int64 = 0
    /// Called on main after a successful download, so the engine can load the model.
    var onDownloaded: ((WhisperModelID) -> Void)?
    /// Called on main after the downloaded models were deleted.
    var onDeleted: (() -> Void)?

    func isLocated(_ id: WhisperModelID) -> Bool { ModelManager.shared.locateModel(id) != nil }

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
        DispatchQueue.global(qos: .utility).async {
            let bytes = ModelManager.shared.managedBytes()
            DispatchQueue.main.async { self.managedBytes = bytes }
        }
    }

    func deleteManagedModels() {
        do {
            try ModelManager.shared.deleteManagedModels()
            pttLog("Deleted downloaded Whisper models")
        } catch {
            pttLog("Deleting models failed: \(error)")
        }
        objectWillChange.send() // isLocated(_:) answers differently now
        onDeleted?()
        refreshManagedSize()
    }
}
