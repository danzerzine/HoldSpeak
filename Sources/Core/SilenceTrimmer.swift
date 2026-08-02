import Foundation

/// Energy-based VAD over 16 kHz mono float samples: trims leading/trailing
/// silence and rejects buffers that are too short or almost entirely silent.
public struct SilenceTrimmer {
    public var windowSamples: Int = 480          // 30 ms at 16 kHz
    public var floor: Float = 0.0008
    public var relative: Float = 0.10            // threshold = max(floor, relative * peak)
    public var paddingMs: Int = 250
    public var minDurationMs: Int = 150
    public var maxSilenceFraction: Float = 0.98

    public init() {}

    /// Trim leading/trailing silence from the buffer and return `nil` if the result
    /// is too short or the input is almost entirely silent.
    public func trimSilence(_ samples: [Float]) -> [Float]? {
        let windowSize = windowSamples
        guard samples.count >= windowSize else { return nil }

        let windowCount = samples.count / windowSize
        var rms = [Float](); rms.reserveCapacity(windowCount)
        var peak: Float = 0
        for w in 0..<windowCount {
            let start = w * windowSize
            var sum: Float = 0
            for i in 0..<windowSize {
                let v = samples[start + i]
                sum += v * v
            }
            let r = (sum / Float(windowSize)).squareRoot()
            rms.append(r)
            if r > peak { peak = r }
        }

        let threshold = max(floor, relative * peak)
        var firstVoice = -1
        var lastVoice = -1
        var silentCount = 0
        for (i, r) in rms.enumerated() {
            if r > threshold {
                if firstVoice < 0 { firstVoice = i }
                lastVoice = i
            } else {
                silentCount += 1
            }
        }
        guard firstVoice >= 0 else { return nil }

        let silentFraction = Float(silentCount) / Float(windowCount)
        if silentFraction > maxSilenceFraction { return nil }

        let paddingWindows = (paddingMs * 16) / windowSize    // 16 samples per ms
        let startWindow = max(0, firstVoice - paddingWindows)
        let endWindow = min(windowCount - 1, lastVoice + paddingWindows)

        let startSample = startWindow * windowSize
        let endSample = min(samples.count, (endWindow + 1) * windowSize)
        let durationMs = (endSample - startSample) / 16
        if durationMs < minDurationMs { return nil }

        return Array(samples[startSample..<endSample])
    }
}
