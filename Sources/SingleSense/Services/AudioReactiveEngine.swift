import Foundation
import Combine
import Accelerate
import AVFoundation
import ScreenCaptureKit

/// Frequency-band energies extracted from the system audio mix, all normalised
/// to `0...1` after automatic gain control.
public struct AudioLevels: Equatable {
    public var bass: Float = 0
    public var mid: Float = 0
    public var treble: Float = 0
    /// Broadband loudness, useful for driving brightness on its own.
    public var overall: Float = 0
    /// Decays from 1 immediately after a detected bass onset.
    public var beat: Float = 0

    public static let silent = AudioLevels()
}

/// Per-band automatic gain control.
///
/// Music has a steep spectral tilt: the bass band routinely carries 20-40 dB
/// more energy than the treble band. Normalising every band against one shared
/// peak therefore pins treble near zero — which leaves the right rumble motor
/// and the blue channel permanently idle no matter how bright the hi-hats are.
/// Each band tracks its own peak instead, with a floor tied to the overall peak
/// so a silent band cannot be amplified up into its own noise.
struct BandNormalizer {
    /// Below this the mix counts as silence and every band reads zero.
    static let silenceThreshold: Float = 1e-4
    /// A band's reference may not fall below this fraction of the loudest
    /// band, which caps how far a very quiet band can be boosted.
    static let relativeFloor: Float = 0.02
    static let absoluteFloor: Float = 0.002

    /// Tracks a signal's recent maximum: jumps up, bleeds down.
    private struct PeakFollower {
        var value: Float = BandNormalizer.absoluteFloor

        mutating func update(_ sample: Float, floor: Float) -> Float {
            value = sample > value
                ? value + (sample - value) * 0.5
                : value * 0.995
            value = max(value, floor)
            return value
        }
    }

    private var overallPeak = PeakFollower()
    private var bassPeak = PeakFollower()
    private var midPeak = PeakFollower()
    private var treblePeak = PeakFollower()

    mutating func reset() { self = BandNormalizer() }

    mutating func normalize(
        bass rawBass: Float,
        mid rawMid: Float,
        treble rawTreble: Float,
        gain: Float
    ) -> AudioLevels {
        let rawOverall = max(rawBass, max(rawMid, rawTreble))
        guard rawOverall.isFinite, rawOverall > Self.silenceThreshold else {
            // Let the followers keep bleeding down, but report silence, so a
            // decaying reference cannot amplify the noise floor to full scale.
            _ = overallPeak.update(0, floor: Self.absoluteFloor)
            _ = bassPeak.update(0, floor: Self.absoluteFloor)
            _ = midPeak.update(0, floor: Self.absoluteFloor)
            _ = treblePeak.update(0, floor: Self.absoluteFloor)
            return .silent
        }

        let overall = overallPeak.update(rawOverall, floor: Self.absoluteFloor)
        let bandFloor = max(Self.absoluteFloor, overall * Self.relativeFloor)

        func shape(_ raw: Float, _ peak: Float) -> Float {
            let scaled = (raw * gain) / peak
            guard scaled.isFinite else { return 0 }
            // A mild curve keeps mid-level material from washing out.
            return min(max(powf(min(scaled, 1), 0.7), 0), 1)
        }

        return AudioLevels(
            bass: shape(rawBass, bassPeak.update(rawBass, floor: bandFloor)),
            mid: shape(rawMid, midPeak.update(rawMid, floor: bandFloor)),
            treble: shape(rawTreble, treblePeak.update(rawTreble, floor: bandFloor)),
            overall: shape(rawOverall, overall),
            beat: 0
        )
    }
}

public enum AudioCaptureStatus: Equatable {
    case idle
    case starting
    case running
    /// Screen Recording permission has not been granted to SingleSense.
    case permissionRequired
    case failed(String)

    public var isActive: Bool {
        self == .starting || self == .running
    }
}

/// Taps the system audio mix through ScreenCaptureKit and reduces it to the
/// handful of numbers the lightbar needs.
///
/// ScreenCaptureKit is the only way to observe system output on macOS without
/// asking the user to install a loopback audio driver. It is gated behind the
/// Screen Recording permission even when no video frames are used.
public final class AudioReactiveEngine: NSObject, ObservableObject {
    public static let shared = AudioReactiveEngine()

    @Published public private(set) var status: AudioCaptureStatus = .idle
    /// Mirrors `levels` for the UI meters, republished at a rate SwiftUI can
    /// keep up with rather than once per audio buffer.
    @Published public private(set) var displayLevels: AudioLevels = .silent

    /// Read from the 60 Hz lightbar tick. Consumes the analysis queue in
    /// order, up to the present moment on the audio clock.
    public var levels: AudioLevels {
        drain(upTo: CACurrentMediaTime())
    }

    /// Overall gain applied before the automatic level control, `0.25...4`.
    /// Written from the UI, read on the audio queue, hence the lock.
    public var sensitivity: Float {
        get { lock.lock(); defer { lock.unlock() }; return storedSensitivity }
        set { lock.lock(); storedSensitivity = min(max(newValue, 0.25), 4); lock.unlock() }
    }

    /// 0 = instant response, 1 = heavily damped.
    public var smoothing: Float {
        get { lock.lock(); defer { lock.unlock() }; return storedSmoothing }
        set { lock.lock(); storedSmoothing = min(max(newValue, 0), 1); lock.unlock() }
    }

    private let lock = NSLock()
    private var storedSensitivity: Float = 1.0
    private var storedSmoothing: Float = 0.35

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.singlesense.audio.samples", qos: .userInitiated)

    // MARK: FFT state

    private static let fftSize = 1024
    private static let log2n = vDSP_Length(10) // 2^10 == fftSize

    private let fft = vDSP.FFT(
        log2n: AudioReactiveEngine.log2n,
        radix: .radix2,
        ofType: DSPSplitComplex.self
    )
    private let hannWindow: [Float] = vDSP.window(
        ofType: Float.self,
        usingSequence: .hanningDenormalized,
        count: AudioReactiveEngine.fftSize,
        isHalfWindow: false
    )
    /// Rolling mono buffer; the FFT consumes it a frame at a time.
    private var pendingSamples: [Float] = []
    private static let sampleRate: Float = 48_000

    // MARK: Envelope, AGC and the analysis queue

    private var envelope = AudioLevels.silent
    private var normalizer = BandNormalizer()
    private var bassAverage: Float = 0
    private var lastBeatTime: TimeInterval = 0
    private var lastPublishTime: TimeInterval = 0

    /// Presentation time of the first sample still sitting in `pendingSamples`.
    private var pendingStartTime: TimeInterval = 0
    private var hasPendingTimeline = false

    /// Buffers analysed frames between the analyser and the 60 Hz consumer.
    private var frameQueue = AnalysisFrameQueue()

    private override init() {
        super.init()
    }

    // MARK: - Control

    /// Starts or stops capture to match `active`. Safe to call repeatedly.
    public func setActive(_ active: Bool) {
        if active {
            guard !status.isActive else { return }
            start()
        } else {
            guard status.isActive else { return }
            stop()
        }
    }

    private func start() {
        status = .starting
        Task { [weak self] in
            guard let self = self else { return }
            do {
                // Throws when Screen Recording has not been granted, which is
                // also what triggers the system prompt the first time.
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard let display = content.displays.first else {
                    await self.setStatus(.failed("No display available to attach the audio tap to."))
                    return
                }

                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: [],
                    exceptingWindows: []
                )

                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = Int(Self.sampleRate)
                config.channelCount = 2
                // Video frames are not used; keep them as cheap as possible.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.queueDepth = 5

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.sampleQueue)
                try await stream.startCapture()

                await self.adopt(stream: stream)
            } catch {
                await self.setStatus(Self.classify(error))
            }
        }
    }

    private func stop() {
        let stream = self.stream
        self.stream = nil
        status = .idle

        lock.lock()
        frameQueue.reset()
        lock.unlock()
        displayLevels = .silent

        // These are only ever touched on the sample queue.
        sampleQueue.async { [weak self] in
            guard let self = self else { return }
            self.envelope = .silent
            self.normalizer.reset()
            self.bassAverage = 0
            self.pendingSamples.removeAll(keepingCapacity: true)
            self.hasPendingTimeline = false
        }

        guard let stream = stream else { return }
        Task {
            try? await stream.stopCapture()
        }
    }

    /// Takes ownership of a stream that finished starting up.
    @MainActor
    private func adopt(stream: SCStream) {
        // A stop() issued while startup was in flight wins; tear the new
        // stream straight back down instead of leaving it running.
        guard status == .starting else {
            Task { try? await stream.stopCapture() }
            return
        }
        self.stream = stream
        status = .running
    }

    @MainActor
    private func setStatus(_ newStatus: AudioCaptureStatus) {
        status = newStatus
    }

    private static func classify(_ error: Error) -> AudioCaptureStatus {
        let nsError = error as NSError
        // SCStreamErrorDomain -3801 is "user declined"; TCC also surfaces as
        // a generic failure before the prompt has ever been answered.
        if nsError.domain == SCStreamError.errorDomain,
           nsError.code == SCStreamError.userDeclined.rawValue {
            return .permissionRequired
        }
        return .failed(nsError.localizedDescription)
    }

    // MARK: - Analysis

    fileprivate func process(sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }

        let presentationTime = sampleBuffer.presentationTimeStamp.seconds
        var mono: [Float] = []
        try? sampleBuffer.withAudioBufferList { bufferList, _ in
            let frameCount = Int(sampleBuffer.numSamples)
            let channels = bufferList.count
            guard frameCount > 0, channels > 0 else { return }

            mono = [Float](repeating: 0, count: frameCount)
            // ScreenCaptureKit hands back deinterleaved 32-bit float, one
            // buffer per channel; average them down to mono.
            for buffer in bufferList {
                guard let raw = buffer.mData else { continue }
                let available = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let usable = min(available, frameCount)
                let samples = raw.bindMemory(to: Float.self, capacity: usable)
                vDSP_vadd(mono, 1, samples, 1, &mono, 1, vDSP_Length(usable))
            }
            var scale = 1 / Float(channels)
            vDSP_vsmul(mono, 1, &scale, &mono, 1, vDSP_Length(frameCount))
        }

        guard !mono.isEmpty, presentationTime.isFinite else { return }

        // Anchor the accumulator to the audio clock, and resynchronise on a
        // gap so a dropped or restarted stream cannot skew every later frame.
        let expected = pendingStartTime + Double(pendingSamples.count) / Double(Self.sampleRate)
        if !hasPendingTimeline || abs(presentationTime - expected) > 0.05 {
            pendingSamples.removeAll(keepingCapacity: true)
            pendingStartTime = presentationTime
            hasPendingTimeline = true
        }

        pendingSamples.append(contentsOf: mono)

        let frameSize = Self.fftSize
        let hop = frameSize / 2 // 50% overlap
        var produced: [AnalysisFrame] = []

        while pendingSamples.count >= frameSize {
            let frame = Array(pendingSamples[0..<frameSize])
            // The window is "heard" at its end, so that is the instant this
            // measurement describes.
            let frameTime = pendingStartTime + Double(frameSize) / Double(Self.sampleRate)
            analyse(frame: frame)
            produced.append(AnalysisFrame(time: frameTime, levels: envelope))

            pendingSamples.removeFirst(hop)
            pendingStartTime += Double(hop) / Double(Self.sampleRate)
        }

        guard !produced.isEmpty else { return }

        lock.lock()
        frameQueue.append(contentsOf: produced)
        lock.unlock()

        // Throttle the SwiftUI meters to ~30 Hz.
        let now = CACurrentMediaTime()
        if now - lastPublishTime >= 1.0 / 30.0 {
            lastPublishTime = now
            let newest = produced[produced.count - 1].levels
            DispatchQueue.main.async { [weak self] in
                self?.displayLevels = newest
            }
        }
    }

    /// Consumes the analysis queue in order, up to the present moment.
    fileprivate func drain(upTo now: TimeInterval) -> AudioLevels {
        lock.lock()
        defer { lock.unlock() }
        return frameQueue.drain(upTo: now)
    }

    private func analyse(frame: [Float]) {
        let n = Self.fftSize
        let half = n / 2

        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, hannWindow, 1, &windowed, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPtr in
            imaginary.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                // Pack the real signal into the split-complex layout the
                // real-to-complex FFT expects.
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { typed in
                        vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(half))
                    }
                }

                fft?.forward(input: split, output: &split)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        let binWidth = Self.sampleRate / Float(n)
        func energy(from lowHz: Float, to highHz: Float) -> Float {
            let first = max(1, Int(lowHz / binWidth))
            let last = min(half - 1, Int(highHz / binWidth))
            guard last >= first else { return 0 }
            var sum: Float = 0
            for i in first...last { sum += magnitudes[i] }
            // Magnitudes are squared; RMS keeps the scale perceptually sane.
            return sqrt(sum / Float(last - first + 1))
        }

        lock.lock()
        let gain = storedSensitivity
        let damping = storedSmoothing
        lock.unlock()

        let target = normalizer.normalize(
            bass: energy(from: 20, to: 250),
            mid: energy(from: 250, to: 2_000),
            treble: energy(from: 2_000, to: 8_000),
            gain: gain
        )

        // Asymmetric envelope: snap up on transients, ease down afterwards.
        let attack = 1 - (0.45 * damping)
        let release = 0.30 - (0.22 * damping)
        func follow(_ current: Float, _ next: Float) -> Float {
            let rate = next > current ? attack : release
            return current + (next - current) * rate
        }

        envelope.bass = follow(envelope.bass, target.bass)
        envelope.mid = follow(envelope.mid, target.mid)
        envelope.treble = follow(envelope.treble, target.treble)
        envelope.overall = follow(envelope.overall, target.overall)

        // Onset detection on the bass band, with a refractory period so a
        // sustained note does not register as a run of beats.
        bassAverage += (target.bass - bassAverage) * 0.05
        let now = CACurrentMediaTime()
        if target.bass > bassAverage * 1.4, target.bass > 0.25, now - lastBeatTime > 0.12 {
            lastBeatTime = now
            envelope.beat = 1
        } else {
            envelope.beat = max(0, envelope.beat - 0.08)
        }
    }
}

// MARK: - ScreenCaptureKit plumbing

extension AudioReactiveEngine: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        process(sampleBuffer: sampleBuffer)
    }
}

extension AudioReactiveEngine: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self = self, self.stream === stream else { return }
            self.stream = nil
            self.status = Self.classify(error)
        }
    }
}
