import AVFoundation
import Combine
import CoreAudio
#if SWIFT_PACKAGE
import ObjCCatch
#endif

public enum AudioRecorderError: Error {
    case invalidInputFormat(sampleRate: Double, channels: UInt32)
    /// The input device changed format while capture was starting.
    case formatChanged
    /// A CoreAudio call did not return within the watchdog timeout.
    case stalled(operation: String)
}

/// Captures microphone audio as 16 kHz mono chunks.
///
/// All AVAudioEngine / CoreAudio work runs on a private serial queue: after sleep/wake
/// or an audio route change HAL calls can block for hours, and doing them on the main
/// thread froze the whole app (and got the hotkey event tap disabled). A watchdog
/// abandons a wedged capture and continues with a fresh engine on a fresh queue.
///
/// Public methods must be called on the main thread; `failures` is delivered on main.
@MainActor
public final class AudioRecorder {
    public let amplitude = PassthroughSubject<Float, Never>()
    public let chunks = PassthroughSubject<AVAudioPCMBuffer, Never>()
    public let failures = PassthroughSubject<Error, Never>()

    /// Real HAL hangs last minutes to hours; Continuity (iPhone) mics can take ~5s to wake.
    public var watchdogTimeout: TimeInterval = 10

    private var capture: Capture

    public init() {
        capture = Capture(amplitude: amplitude, chunks: chunks, failures: failures)
    }

    public func start(input: InputSelection) {
        perform("start") { try $0.start(input: input) }
    }

    /// Lowers the speakers until `stop` (see `OutputDucker`). A no-op unless recording.
    public func duckOutput() {
        perform("duck") { $0.duckOutput() }
    }

    /// `completion` runs on main once capture has stopped (or the stop stalled), after
    /// every chunk captured so far has been delivered.
    public func stop(completion: (@MainActor () -> Void)? = nil) {
        perform("stop", completion: completion) { $0.stop() }
    }

    /// Only touched on main.
    @MainActor private final class Op { var finished = false }

    private func perform(_ label: String,
                         completion: (@MainActor () -> Void)? = nil,
                         _ work: @escaping @Sendable (Capture) throws -> Void) {
        let c = capture
        let op = Op()
        c.queue.async { [weak self] in
            var failure: Error?
            do { try work(c) } catch { failure = error }
            DispatchQueue.main.async {
                guard let self, !op.finished else { return }
                op.finished = true
                if let failure, self.capture === c { self.failures.send(failure) }
                completion?()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdogTimeout) { [weak self] in
            guard let self, !op.finished else { return }
            op.finished = true
            if self.capture === c {
                pttLog("AudioRecorder: \(label) stalled >\(self.watchdogTimeout)s — abandoning audio engine")
                c.abandon()
                self.capture = Capture(amplitude: self.amplitude, chunks: self.chunks, failures: self.failures)
                self.failures.send(AudioRecorderError.stalled(operation: label))
            }
            completion?()
        }
    }
}

/// One engine plus the serial queue that owns it. Every method except `abandon()`
/// runs on `queue`.
// @unchecked Sendable: state is confined to `queue` (`_abandoned` to `abandonLock`); the subjects are only sent to.
private final class Capture: @unchecked Sendable {
    let queue = DispatchQueue(label: "HoldSpeak.audio", qos: .userInitiated)

    private let amplitude: PassthroughSubject<Float, Never>
    private let chunks: PassthroughSubject<AVAudioPCMBuffer, Never>
    private let failures: PassthroughSubject<Error, Never>
    private static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: 16_000, channels: 1, interleaved: false)!

    private var engine: AVAudioEngine?
    private var engineDevice: AudioDeviceID?
    private var configObserver: NSObjectProtocol?
    private var input: InputSelection = .systemDefault
    private var isRecording = false
    private var tapFormat: AVAudioFormat?
    /// Device whose input mute we lifted in `start`; re-muted in `stop`.
    private var mutedDevice: AudioDeviceID?
    private let ducker = OutputDucker()

    private let abandonLock = NSLock()
    private var _abandoned = false
    private var abandoned: Bool { abandonLock.lock(); defer { abandonLock.unlock() }; return _abandoned }

    init(amplitude: PassthroughSubject<Float, Never>,
         chunks: PassthroughSubject<AVAudioPCMBuffer, Never>,
         failures: PassthroughSubject<Error, Never>) {
        self.amplitude = amplitude
        self.chunks = chunks
        self.failures = failures
    }

    /// Called on main when this capture is wedged. Whatever op is stuck finishes
    /// eventually; after that the capture tears itself down and stays silent.
    func abandon() {
        abandonLock.lock(); _abandoned = true; abandonLock.unlock()
        queue.async { [self] in
            teardown()
            restoreMute()
            ducker.restore()
            dropEngine()
        }
    }

    func start(input: InputSelection) throws {
        guard !abandoned, !isRecording else { return }
        self.input = input
        let device = InputDevice.resolve(input)
        if device != engineDevice { dropEngine() }
        unmuteIfNeeded(device ?? InputDevice.defaultID())
        do {
            try startEngine(device: device)
        } catch {
            restoreMute()
            ducker.restore()
            throw error
        }
    }

    func duckOutput() {
        guard !abandoned, isRecording else { return }
        ducker.duck()
    }

    func stop() {
        teardown()
        restoreMute()
        ducker.restore()
    }

    // MARK: - Engine

    private func makeEngine(device: AudioDeviceID?) -> AVAudioEngine {
        let engine = AVAudioEngine()
        if let device, let unit = engine.inputNode.audioUnit {
            var id = device
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                              kAudioUnitScope_Global, 0, &id,
                                              UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr {
                pttLog("AudioRecorder: selecting input device \(device) failed (\(status)) — using system default")
            } else {
                // After an explicit device switch the unit keeps the engine rate (taken from the
                // output device) as its client format; if the two differ (48 kHz mic + 44.1 kHz
                // Bluetooth speakers) the tap never receives buffers. Capture at the mic's own rate.
                var asbd = engine.inputNode.inputFormat(forBus: 0).streamDescription.pointee
                let fmtStatus = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
                                                     kAudioUnitScope_Output, 1, &asbd,
                                                     UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
                if fmtStatus != noErr { pttLog("AudioRecorder: aligning client format to device failed (\(fmtStatus))") }
            }
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in self?.handleConfigurationChange() }
        }
        self.engine = engine
        engineDevice = device
        return engine
    }

    private func dropEngine() {
        if let obs = configObserver { NotificationCenter.default.removeObserver(obs) }
        configObserver = nil
        engine = nil
        engineDevice = nil
    }

    private func startEngine(device: AudioDeviceID?) throws {
        // A Bluetooth device can switch sample rate between reading the format and
        // installing the tap; a fresh engine picks up the new format, so retry once.
        do {
            try startEngineOnce(device: device)
        } catch AudioRecorderError.formatChanged {
            pttLog("AudioRecorder: input format changed during start — retrying with a fresh engine")
            try startEngineOnce(device: device)
        }
    }

    private func startEngineOnce(device: AudioDeviceID?) throws {
        let engine = self.engine ?? makeEngine(device: device)
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let deviceRate = inputNode.inputFormat(forBus: 0).sampleRate
        pttLog("AudioRecorder hwFormat: sampleRate=\(hwFormat.sampleRate) channels=\(hwFormat.channelCount) device=\(deviceRate)")
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            dropEngine()
            throw AudioRecorderError.invalidInputFormat(sampleRate: hwFormat.sampleRate,
                                                        channels: hwFormat.channelCount)
        }
        // deviceRate may legitimately differ from hwFormat: the input unit resamples to the
        // engine rate (e.g. 48 kHz mic + 44.1 kHz Bluetooth speakers). A real mid-start
        // format switch surfaces as an installTap exception below.
        let monoHW = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hwFormat.sampleRate,
                                   channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: monoHW, to: Self.targetFormat) else {
            dropEngine()
            throw AudioRecorderError.invalidInputFormat(sampleRate: hwFormat.sampleRate,
                                                        channels: hwFormat.channelCount)
        }

        // Only the audio tap thread touches these (the tap callback is serial).
        nonisolated(unsafe) var tapCount = 0
        var objcError: NSError?
        let installed = HSCatchObjCException({
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
                guard let self, !self.abandoned else { return }
                tapCount += 1
                if tapCount <= 3 || tapCount % 50 == 0 {
                    pttLog("tap #\(tapCount) frames=\(buffer.frameLength) rms=\(Self.rms(buffer))")
                }
                guard let out = Self.convert(buffer, monoFormat: monoHW, converter: converter) else { return }
                self.amplitude.send(Self.rms(out))
                self.chunks.send(out)
            }
            engine.prepare()
        }, &objcError)
        guard installed else {
            pttLog("AudioRecorder: installTap raised \(objcError?.localizedDescription ?? "?") — rebuilding engine")
            dropEngine()
            throw AudioRecorderError.formatChanged
        }
        do {
            var startError: NSError?
            var thrown: Error?
            if !HSCatchObjCException({
                do { try engine.start() } catch { thrown = error }
            }, &startError) {
                throw startError ?? AudioRecorderError.formatChanged
            }
            if let thrown { throw thrown }
        } catch {
            pttLog("engine.start failed: \(error) — rebuilding engine")
            _ = HSCatchObjCException({ inputNode.removeTap(onBus: 0) }, nil)
            dropEngine()
            throw error
        }
        tapFormat = hwFormat
        isRecording = true
    }

    private func teardown() {
        guard isRecording, let engine else { isRecording = false; return }
        _ = HSCatchObjCException({
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }, nil)
        isRecording = false
    }

    /// Bluetooth headsets switch profile (e.g. A2DP → HFP, 48 kHz → 16/24 kHz) once the mic
    /// opens, and devices come and go on sleep/wake. The old engine is unusable either way,
    /// so rebuild; mid-recording, resume capture so the take isn't silently dropped.
    private func handleConfigurationChange() {
        guard !abandoned else { return }
        // Selecting a specific device fires a change right after start while the engine
        // keeps running in the same format — rebuilding then would drop the first second.
        if let engine, engine.isRunning, let tapFormat,
           engine.inputNode.outputFormat(forBus: 0).sampleRate == tapFormat.sampleRate,
           engine.inputNode.outputFormat(forBus: 0).channelCount == tapFormat.channelCount {
            pttLog("AVAudioEngineConfigurationChange ignored (engine still running, format unchanged)")
            return
        }
        pttLog("AVAudioEngineConfigurationChange (recording=\(isRecording)) — resetting engine")
        let wasRecording = isRecording
        teardown()
        dropEngine()
        guard wasRecording else { return }
        do {
            try startEngine(device: InputDevice.resolve(input))
            pttLog("AudioRecorder: capture resumed after configuration change")
        } catch {
            pttLog("AudioRecorder: resume after configuration change failed: \(error)")
            restoreMute()
            ducker.restore()
            DispatchQueue.main.async { self.failures.send(error) }
        }
    }

    // MARK: - Device mute

    private func unmuteIfNeeded(_ id: AudioDeviceID?) {
        guard let id else { return }
        pttLog("AudioRecorder input device: \(InputDevice.describe(id))")
        guard InputDevice.isMuted(id) == true else { return }
        if InputDevice.setMuted(id, false) {
            mutedDevice = id
            pttLog("AudioRecorder: input was muted at device level — unmuted for recording")
        } else {
            pttLog("AudioRecorder: input is muted at device level and cannot be unmuted")
        }
    }

    private func restoreMute() {
        guard let id = mutedDevice else { return }
        mutedDevice = nil
        InputDevice.setMuted(id, true)
    }

    // MARK: - DSP

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        return (sum / Float(n)).squareRoot()
    }

    private static func convert(_ buffer: AVAudioPCMBuffer,
                                monoFormat: AVAudioFormat,
                                converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard let mono = downmixToMono(buffer, monoFormat: monoFormat) else { return nil }
        let ratio = targetFormat.sampleRate / monoFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(mono.frameLength) * ratio + 128)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var err: NSError?
        // The input block runs synchronously inside `convert(to:error:)`.
        nonisolated(unsafe) var didProvide = false
        nonisolated(unsafe) let provided = mono
        converter.convert(to: out, error: &err) { _, status in
            if didProvide { status.pointee = .noDataNow; return nil }
            didProvide = true
            status.pointee = .haveData
            return provided
        }
        guard err == nil, out.frameLength > 0 else { return nil }
        return out
    }

    private static func downmixToMono(_ src: AVAudioPCMBuffer, monoFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = src.frameLength
        guard frames > 0, let channelData = src.floatChannelData else { return nil }
        let channels = Int(src.format.channelCount)
        guard let out = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frames),
              let dst = out.floatChannelData?[0] else { return nil }
        out.frameLength = frames
        let n = Int(frames)
        if channels == 1 {
            memcpy(dst, channelData[0], n * MemoryLayout<Float>.size)
        } else {
            let inv = 1.0 / Float(channels)
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += channelData[c][i] }
                dst[i] = sum * inv
            }
        }
        return out
    }
}
