import Foundation
import Combine
import Accelerate
import CoreAudio
import AudioToolbox
import QuartzCore
import AppKit

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
    /// System Audio Recording permission has not been granted.
    case permissionRequired
    case relaunchRequired
    case failed(String)

    public var isActive: Bool {
        self == .starting || self == .running
    }
}

/// Taps the system audio mix through native Core Audio Process Taps and reduces it to the
/// handful of numbers the lightbar needs.
///
/// Uses Apple's native Core Audio Process Tap (`AudioHardwareCreateProcessTap`),
/// which captures system audio output directly without requiring Screen Recording permissions
/// or third-party virtual audio drivers.
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

    // Core Audio Tap state
    private var tapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?

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

    private var wantsCapture = false

    private override init() {
        super.init()
    }

    // MARK: - Control

    /// Starts or stops capture to match `active`. Safe to call repeatedly.
    public func setActive(_ active: Bool) {
        wantsCapture = active
        if active {
            guard !status.isActive else { return }
            start()
        } else {
            guard status.isActive else {
                status = .idle
                return
            }
            stop()
        }
    }

    public func requestPermission() {
        start()
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func relaunchApp() {
        PermissionMonitor.shared.relaunch()
    }

    private func start() {
        guard aggregateDeviceID == 0 else { return }
        guard #available(macOS 14.2, *) else {
            status = .failed("System Audio Recording requires macOS 14.2 or later")
            return
        }
        status = .starting

        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapStatus == noErr else {
            if tapStatus == 1852797029 /* 'nope' */ || tapStatus == -50 {
                status = .permissionRequired
            } else {
                status = .failed("Failed to create audio tap (code \(tapStatus))")
            }
            return
        }

        let tapConfig: [String: Any] = [
            kAudioSubTapUIDKey as String: tapDesc.uuid.uuidString,
            kAudioSubTapDriftCompensationKey as String: true
        ]

        let uid = UUID().uuidString
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "SingleSenseAudioTap",
            kAudioAggregateDeviceUIDKey as String: uid,
            kAudioAggregateDeviceTapListKey as String: [tapConfig],
            kAudioAggregateDeviceIsPrivateKey as String: true
        ]

        var newDeviceID: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newDeviceID)
        guard aggStatus == noErr else {
            AudioHardwareDestroyProcessTap(newTapID)
            status = .failed("Failed to create Aggregate Device (code \(aggStatus))")
            return
        }

        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, newDeviceID, nil) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            self?.handleAudioInput(inInputData: inInputData, inInputTime: inInputTime)
        }

        guard procStatus == noErr, let validProcID = newProcID else {
            AudioHardwareDestroyAggregateDevice(newDeviceID)
            AudioHardwareDestroyProcessTap(newTapID)
            status = .failed("Failed to create audio callback (code \(procStatus))")
            return
        }

        let startStatus = AudioDeviceStart(newDeviceID, validProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(newDeviceID, validProcID)
            AudioHardwareDestroyAggregateDevice(newDeviceID)
            AudioHardwareDestroyProcessTap(newTapID)
            if startStatus == 1852797029 /* 'nope' */ {
                status = .permissionRequired
            } else {
                status = .failed("Audio tap rejected (code \(startStatus))")
            }
            return
        }

        self.tapID = newTapID
        self.aggregateDeviceID = newDeviceID
        self.procID = validProcID
        self.status = .running
    }

    private func stop() {
        if let procID = self.procID, aggregateDeviceID != 0 {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            self.procID = nil
        }
        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
        if #available(macOS 14.2, *), tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        status = .idle

        lock.lock()
        frameQueue.reset()
        lock.unlock()
        displayLevels = .silent

        sampleQueue.async { [weak self] in
            guard let self = self else { return }
            self.envelope = .silent
            self.normalizer.reset()
            self.bassAverage = 0
            self.lastBeatTime = 0
            self.pendingSamples.removeAll(keepingCapacity: true)
            self.hasPendingTimeline = false
        }
    }

    // MARK: - Analysis

    private func handleAudioInput(inInputData: UnsafePointer<AudioBufferList>, inInputTime: UnsafePointer<AudioTimeStamp>) {
        let bufferList = inInputData.pointee
        guard bufferList.mNumberBuffers > 0 else { return }
        let buffer = bufferList.mBuffers
        guard let raw = buffer.mData, buffer.mNumberChannels > 0 else { return }

        let channels = Int(buffer.mNumberChannels)
        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let frameCount = totalSamples / channels
        guard frameCount > 0 else { return }

        let ptr = raw.assumingMemoryBound(to: Float.self)
        var mono = [Float](repeating: 0, count: frameCount)

        if channels == 1 {
            mono.withUnsafeMutableBufferPointer { dest in
                _ = dest.baseAddress?.initialize(from: ptr, count: frameCount)
            }
        } else if channels == 2 {
            for i in 0..<frameCount {
                mono[i] = (ptr[i * 2] + ptr[i * 2 + 1]) * 0.5
            }
        } else {
            let scale = 1.0 / Float(channels)
            for i in 0..<frameCount {
                var sum: Float = 0
                for c in 0..<channels {
                    sum += ptr[i * channels + c]
                }
                mono[i] = sum * scale
            }
        }

        let presentationTime: TimeInterval
        if inInputTime.pointee.mFlags.contains(.hostTimeValid) {
            let hostTime = inInputTime.pointee.mHostTime
            presentationTime = Double(hostTime) / 1_000_000_000.0
        } else {
            presentationTime = CACurrentMediaTime()
        }

        sampleQueue.async { [weak self] in
            self?.process(mono: mono, presentationTime: presentationTime)
        }
    }

    private func process(mono: [Float], presentationTime: TimeInterval) {
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
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                windowed.withUnsafeBufferPointer { w in
                    w.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { c in
                        vDSP_ctoz(c, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft?.forward(input: split, output: &split)
            }
        }

        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeBufferPointer { r in
            imaginary.withUnsafeBufferPointer { i in
                var split = DSPSplitComplex(realp: UnsafeMutablePointer(mutating: r.baseAddress!), imagp: UnsafeMutablePointer(mutating: i.baseAddress!))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        var scale = 1.0 / Float(n)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(half))

        let binWidth = Self.sampleRate / Float(n)

        func bandEnergy(from lowHz: Float, to highHz: Float) -> Float {
            let start = max(1, Int(lowHz / binWidth))
            let end = min(half - 1, Int(highHz / binWidth))
            guard start < end else { return 0 }
            var sum: Float = 0
            vDSP_sve(Array(magnitudes[start...end]), 1, &sum, vDSP_Length(end - start + 1))
            return sqrtf(sum / Float(end - start + 1))
        }

        let rawBass = bandEnergy(from: 20, to: 250)
        let rawMid = bandEnergy(from: 250, to: 4000)
        let rawTreble = bandEnergy(from: 4000, to: 16000)

        lock.lock()
        let gain = storedSensitivity
        lock.unlock()

        let normalized = normalizer.normalize(
            bass: rawBass,
            mid: rawMid,
            treble: rawTreble,
            gain: gain
        )

        updateEnvelope(target: normalized)
    }

    private func updateEnvelope(target: AudioLevels) {
        lock.lock()
        let smooth = storedSmoothing
        lock.unlock()

        let attack: Float = 0.6
        let decay = max(0.05, 0.4 * (1.0 - smooth))

        func follow(_ current: Float, _ next: Float) -> Float {
            let coeff = next > current ? attack : decay
            return current + (next - current) * coeff
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
