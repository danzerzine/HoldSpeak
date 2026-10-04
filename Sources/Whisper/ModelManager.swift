import Foundation
import WhisperKit
import FluidAudio

public final class ModelManager {
    public static let shared = ModelManager()
    private init() {}

    public func managedDirectory() -> URL {
        AppPaths.support.appendingPathComponent("models")
    }

    public func downloadCacheDirectory() -> URL {
        AppPaths.support.appendingPathComponent("hf-cache")
    }

    public func macWhisperDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacWhisper/models/whisperkit/models/argmaxinc/whisperkit-coreml")
    }

    /// Default download base used by `swift-transformers` / WhisperKit when no
    /// `downloadBase` is supplied. Other WhisperKit-powered apps (and older
    /// builds of this app) drop CoreML models here, so we probe it to avoid
    /// re-downloading gigabytes the user already has.
    public func externalWhisperKitDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
    }

    public func locateModel(_ id: WhisperModelID) -> URL? {
        if id.isParakeet { return locateParakeet() }
        let fm = FileManager.default
        let managed = managedDirectory().appendingPathComponent(id.rawValue)
        if fm.fileExists(atPath: managed.path) { return managed }
        let macWhisper = macWhisperDirectory().appendingPathComponent(id.rawValue)
        if fm.fileExists(atPath: macWhisper.path) { return macWhisper }
        let external = externalWhisperKitDirectory().appendingPathComponent(id.rawValue)
        if fm.fileExists(atPath: external.path), fm.isReadableFile(atPath: external.path) {
            return external
        }
        return nil
    }

    /// Parakeet: the app's own folder, then FluidAudio's default cache (other
    /// FluidAudio apps). A folder only counts once every model file is in it.
    private func locateParakeet() -> URL? {
        let managed = managedDirectory().appendingPathComponent(WhisperModelID.parakeetUltra.rawValue)
        for dir in [managed, AsrModels.defaultCacheDirectory(for: .ultra)]
        where AsrModels.modelsExist(at: dir, version: .ultra) {
            return dir
        }
        return nil
    }

    /// True when the app itself has downloaded at least one model (older versions
    /// fetched one automatically on first launch).
    public func hasManagedModels() -> Bool {
        let items = try? FileManager.default.contentsOfDirectory(atPath: managedDirectory().path)
        return items?.contains { !$0.hasPrefix(".") } == true
    }

    /// Bytes on disk in the folders the app downloads into. Models found in
    /// MacWhisper's or ~/Documents' folders belong to other apps and are not counted.
    public func managedBytes() -> Int64 {
        [managedDirectory(), downloadCacheDirectory()].reduce(0) { $0 + Self.size(of: $1) }
    }

    /// Deletes everything the app downloaded; other apps' models are left alone.
    public func deleteManagedModels() throws {
        let fm = FileManager.default
        for dir in [managedDirectory(), downloadCacheDirectory()] where fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
    }

    private static func size(of dir: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    public func download(_ id: WhisperModelID,
                         progress: @escaping (Double) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: managedDirectory(), withIntermediateDirectories: true)
        if id.isParakeet {
            return try await AsrModels.download(
                to: managedDirectory().appendingPathComponent(id.rawValue),
                version: .ultra,
                progressHandler: { p in progress(p.fractionCompleted) }
            )
        }
        try FileManager.default.createDirectory(at: downloadCacheDirectory(), withIntermediateDirectories: true)
        let downloaded = try await WhisperKit.download(
            variant: id.rawValue,
            downloadBase: downloadCacheDirectory(),
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: { p in progress(p.fractionCompleted) }
        )
        let dst = managedDirectory().appendingPathComponent(id.rawValue)
        if downloaded.path != dst.path {
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.moveItem(at: downloaded, to: dst)
            if !FileManager.default.fileExists(atPath: dst.path) { return downloaded }
        }
        return dst
    }
}
