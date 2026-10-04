import AudioToolbox
import CoreAudio
import Foundation

/// Lowers the default output device's volume while a recording runs, so music from the
/// speakers doesn't bleed into the mic. Plain volume control, not voice processing: Apple's
/// mic modes (Voice Isolation) crash virtual output drivers such as Boom 3D.
///
/// Restores only the device it lowered, and only if the volume is still where it left it,
/// so a manual change during the recording wins. The pending restore is persisted, so a
/// crash mid-recording is undone on the next launch.
public final class OutputDucker {
    /// Volume while recording, as a fraction of the volume before it.
    public static let factor: Float32 = 0.2
    private static let pendingKey = "outputDuckPending"

    private struct Pending: Codable {
        let uid: String
        let original: Float32
        let ducked: Float32
    }

    private var pending: Pending?
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func duck() {
        guard pending == nil,
              let id = Self.defaultOutputID(),
              let uid = Self.uid(id),
              let original = Self.volume(id), original > 0 else { return }
        let target = original * Self.factor
        guard Self.setVolume(id, target), let ducked = Self.volume(id) else {
            pttLog("OutputDucker: output volume not settable — not ducking")
            return
        }
        let p = Pending(uid: uid, original: original, ducked: ducked)
        pending = p
        defaults.set(try? JSONEncoder().encode(p), forKey: Self.pendingKey)
        pttLog(String(format: "OutputDucker: output %.3f → %.3f", original, ducked))
    }

    public func restore() {
        guard let p = pending else { return }
        pending = nil
        Self.apply(p)
        defaults.removeObject(forKey: Self.pendingKey)
    }

    /// Undoes a duck left behind by a crash or force quit.
    public func restoreAfterCrash() {
        guard pending == nil,
              let data = defaults.data(forKey: Self.pendingKey),
              let p = try? JSONDecoder().decode(Pending.self, from: data) else { return }
        pttLog("OutputDucker: restoring volume left ducked by the previous run")
        Self.apply(p)
        defaults.removeObject(forKey: Self.pendingKey)
    }

    private static func apply(_ p: Pending) {
        guard let id = device(uid: p.uid), let now = volume(id) else {
            pttLog("OutputDucker: ducked device gone — nothing to restore")
            return
        }
        guard abs(now - p.ducked) < 0.01 else {
            pttLog(String(format: "OutputDucker: volume changed to %.3f during recording — keeping it", now))
            return
        }
        if !setVolume(id, p.original) { pttLog("OutputDucker: restoring volume failed") }
    }

    // MARK: - CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func uid(_ id: AudioDeviceID) -> String? {
        var addr = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private static func device(uid: String) -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// The main volume as the menu bar slider shows it, also for devices that only have
    /// per-channel controls.
    private static var volumeAddress: AudioObjectPropertyAddress {
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
    }

    private static func volume(_ id: AudioDeviceID) -> Float32? {
        var addr = volumeAddress
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    private static func setVolume(_ id: AudioDeviceID, _ value: Float32) -> Bool {
        var addr = volumeAddress
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &addr),
              AudioObjectIsPropertySettable(id, &addr, &settable) == noErr,
              settable.boolValue else { return false }
        var v = value
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }
}
