import Foundation
import Combine
import CoreAudio
import AudioToolbox
import os

// The DualSense's real haptics: two voice-coil actuators in the grips.
//
// Over USB the controller is a four-channel sound card and channels 3-4 *are*
// the coils — whatever waveform lands there is what the hands feel. The
// rumble motors in the output report are only the firmware imitating old
// eccentric-mass motors on those same coils. Driving the channels directly
// gives sharp clicks, textures and pitch, and lets the music reach the grips
// as the music itself rather than as a level.
//
// The synthesis is ported from Licor's desktop haptics (`Haptics_sdl.cpp`):
// decaying sines for the body of an effect, low-passed noise for its texture,
// everything rendered at the controller's 48 kHz.

// MARK: - Synthesis

/// xorshift32: the same noise for the same effect, every time.
struct HapticRandom {
    private var state: UInt32

    init(seed: UInt32) { state = seed != 0 ? seed : 0x1234567 }

    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// `0..<1`
    mutating func unit() -> Float { Float(next() >> 8) / 16_777_216 }
    /// `-1..<1`
    mutating func sign() -> Float { unit() * 2 - 1 }
    mutating func range(_ low: Float, _ high: Float) -> Float { low + (high - low) * unit() }
}

/// A mono waveform under construction. Layers add into it; every layer's
/// exponential decay reaches -60 dB after its `decayMs`.
struct HapticWave {
    static let sampleRate: Float = 48_000

    private(set) var samples: [Float]

    init(milliseconds: Float) {
        samples = [Float](repeating: 0, count: max(0, Int(milliseconds * Self.sampleRate * 0.001)))
    }

    private func index(at milliseconds: Float) -> Int {
        min(samples.count, Int(max(0, milliseconds) * Self.sampleRate * 0.001))
    }

    static func envelope(_ t: Float, attack: Float, decay: Float) -> Float {
        let rise = attack > 0 ? min(1, t / attack) : 1
        return rise * expf(-6.9078 * t / decay)
    }

    /// A decaying sine, optionally gliding from `hz` to `endHz` over its decay.
    mutating func addSine(
        _ hz: Float, _ amplitude: Float, attackMs: Float, decayMs: Float,
        delayMs: Float = 0, endHz: Float = 0
    ) {
        let start = index(at: delayMs)
        let decay = decayMs * 0.001
        let attack = max(attackMs, 0.8) * 0.001
        var phase = 0.0
        var i = start
        while i < samples.count {
            let t = Float(i - start) / Self.sampleRate
            if t > decay * 1.1 { break }
            let frequency = endHz > 0 ? hz + (endHz - hz) * min(1, t / decay) : hz
            phase += 2 * Double.pi * Double(frequency) / Double(Self.sampleRate)
            samples[i] += amplitude * Self.envelope(t, attack: attack, decay: decay) * Float(sin(phase))
            i += 1
        }
    }

    /// Low-passed noise, the texture layer. Two one-pole stages: the coils
    /// have nothing to say above ~500 Hz, and hiss is not a texture.
    /// `amplitude` is that of a sine with the same RMS, so noise and sine
    /// layers balance. `grain` breaks it into random 2 ms grains (gravel, sand).
    mutating func addNoise(
        _ random: inout HapticRandom, cutoffHz: Float, _ amplitude: Float,
        attackMs: Float, decayMs: Float, delayMs: Float = 0, grain: Float = 0
    ) {
        let start = index(at: delayMs)
        let decay = decayMs * 0.001
        let attack = max(attackMs, 0.8) * 0.001
        let coefficient = 1 - expf(-2 * Float.pi * cutoffHz / Self.sampleRate)
        let length = max(0, min(samples.count - start, Int(decay * 1.1 * Self.sampleRate) + 1))
        guard length > 0 else { return }

        var noise = [Float](repeating: 0, count: length)
        var stage1: Float = 0, stage2: Float = 0, grainGain: Float = 1
        let grainLength = Int(0.002 * Self.sampleRate)
        var noiseSquares = 0.0, envelopeSquares = 0.0
        for i in 0..<length {
            let t = Float(i) / Self.sampleRate
            if grain > 0, i % grainLength == 0 { grainGain = 1 - grain + grain * random.unit() }
            stage1 += coefficient * (random.sign() - stage1)
            stage2 += coefficient * (stage1 - stage2)
            let shape = Self.envelope(t, attack: attack, decay: decay)
            noise[i] = stage2 * grainGain * shape
            noiseSquares += Double(noise[i] * noise[i])
            envelopeSquares += Double(shape * shape)
        }
        guard noiseSquares > 0 else { return }
        let gain = amplitude * Float((0.5 * envelopeSquares / noiseSquares).squareRoot())
        for i in 0..<length { samples[start + i] += gain * noise[i] }
    }

    /// Normalises so the loudest sample is `peak`, and fades the last 2 ms so
    /// the coil never sees a step.
    func finished(peak: Float) -> [Float] {
        var out = samples
        let loudest = out.reduce(0) { max($0, abs($1)) }
        let scale = loudest > 0 ? min(max(peak, 0), 1) / loudest : 0
        for i in out.indices { out[i] *= scale }
        let fade = min(out.count, Int(0.002 * Self.sampleRate))
        for i in 0..<fade { out[out.count - 1 - i] *= Float(i) / Float(max(fade, 1)) }
        return out
    }
}

/// One waveform placed in time and between the two grips.
public struct HapticCue {
    public var samples: [Float]
    /// `-1` left grip … `+1` right grip.
    public var pan: Float = 0
    public var delayMs: Float = 0
}

public enum HapticPreset: String, CaseIterable, Identifiable {
    case click = "Crisp Click"
    case thud = "Heavy Thud"
    case heartbeat = "Heartbeat"
    case burst = "Rapid Burst"
    case knock = "Wood Knock"
    case footsteps = "Gravel Steps"
    case rain = "Rain"
    case explosion = "Explosion"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .click: return "hand.tap.fill"
        case .thud: return "arrow.down.to.line.compact"
        case .heartbeat: return "heart.fill"
        case .burst: return "burst.fill"
        case .knock: return "door.left.hand.closed"
        case .footsteps: return "figure.walk"
        case .rain: return "cloud.rain.fill"
        case .explosion: return "flame.fill"
        }
    }

    /// The closest CoreHaptics pattern, for when the coils cannot be reached.
    public var fallbackPattern: String {
        switch self {
        case .click, .knock, .rain: return "click"
        case .thud, .explosion: return "thud"
        case .heartbeat: return "heartbeat"
        case .burst, .footsteps: return "burst"
        }
    }

    /// Effects that only make sense on the coils; the motors can only hint.
    public var needsVoiceCoils: Bool {
        switch self {
        case .knock, .footsteps, .rain, .explosion: return true
        case .click, .thud, .heartbeat, .burst: return false
        }
    }

    public func cues() -> [HapticCue] {
        switch self {
        case .click:
            var random = HapticRandom(seed: 0xA990_4000)
            var wave = HapticWave(milliseconds: 45)
            wave.addSine(230, 0.8, attackMs: 0.8, decayMs: 15)
            wave.addNoise(&random, cutoffHz: 600, 0.5, attackMs: 0.8, decayMs: 7)
            return [HapticCue(samples: wave.finished(peak: 0.6))]

        case .thud:
            var random = HapticRandom(seed: 0x1A4D_1000)
            var wave = HapticWave(milliseconds: 310)
            wave.addSine(56, 1, attackMs: 1.5, decayMs: 184, endHz: 40)
            wave.addSine(104, 0.5, attackMs: 1, decayMs: 64)
            wave.addNoise(&random, cutoffHz: 150, 0.4, attackMs: 1, decayMs: 91)
            return [HapticCue(samples: wave.finished(peak: 0.75))]

        case .heartbeat:
            var random = HapticRandom(seed: 0xDA3A_6000)
            var wave = HapticWave(milliseconds: 520)
            wave.addSine(70, 1, attackMs: 2, decayMs: 110, endHz: 55)
            wave.addSine(64, 0.75, attackMs: 2, decayMs: 140, delayMs: 190, endHz: 48)
            wave.addNoise(&random, cutoffHz: 200, 0.25, attackMs: 2, decayMs: 60)
            let beat = wave.finished(peak: 0.7)
            return [HapticCue(samples: beat), HapticCue(samples: beat, delayMs: 850)]

        case .burst:
            var random = HapticRandom(seed: 0xF00D_0000)
            var wave = HapticWave(milliseconds: 75)
            wave.addSine(190, 1, attackMs: 1, decayMs: 26, endHz: 120)
            wave.addSine(330, 0.5, attackMs: 1, decayMs: 12)
            wave.addNoise(&random, cutoffHz: 900, 0.55, attackMs: 0.8, decayMs: 7)
            let shot = wave.finished(peak: 0.65)
            return (0..<6).map { HapticCue(samples: shot, delayMs: Float($0) * 70) }

        case .knock:
            // Licor's wood block break at medium hardness: a knock and a splinter.
            var random = HapticRandom(seed: 0xB4EA_0000 + 613)
            let u: Float = 0.5
            var wave = HapticWave(milliseconds: 90 + 330 * u)
            let f0 = 165 - 95 * u
            wave.addSine(f0, 1, attackMs: 1, decayMs: 38 + 190 * u, endHz: f0 * 0.7)
            wave.addSine(128, 0.6, attackMs: 1.5, decayMs: 55 + 60 * u)
            wave.addSine(232, 0.4, attackMs: 1.5, decayMs: 28)
            for i in 0..<2 {
                wave.addSine(random.range(280, 420), random.range(0.25, 0.5), attackMs: 0.8, decayMs: 8,
                             delayMs: 12 + Float(i) * 17)
            }
            wave.addNoise(&random, cutoffHz: 460, 0.3, attackMs: 1, decayMs: 30)
            return [HapticCue(samples: wave.finished(peak: 0.63))]

        case .footsteps:
            // Gravel underfoot, alternating feet: left grip, right grip.
            return (0..<4).map { step in
                var random = HapticRandom(seed: 0xF00D_0000 + 4 * 977 + UInt32(step & 3) * 31)
                let pitch = 1 + 0.06 * Float(step & 3) - 0.09
                var wave = HapticWave(milliseconds: 140)
                wave.addSine(92 * pitch, 0.5, attackMs: 3, decayMs: 38)
                wave.addNoise(&random, cutoffHz: 260, 0.4, attackMs: 4, decayMs: 70, grain: 0.8)
                for _ in 0..<8 {
                    wave.addSine(random.range(240, 380) * pitch, random.range(0.25, 0.7), attackMs: 0.8,
                                 decayMs: random.range(5, 10), delayMs: random.range(0, 95))
                }
                return HapticCue(samples: wave.finished(peak: 0.55), pan: step.isMultiple(of: 2) ? -1 : 1,
                                 delayMs: Float(step) * 420)
            }

        case .rain:
            var timing = HapticRandom(seed: 0x4A1D_FFFF)
            return (0..<22).map { drop in
                let variant = UInt32(drop & 3)
                var random = HapticRandom(seed: 0x4A1D_0000 + variant * 53)
                var wave = HapticWave(milliseconds: 24)
                wave.addSine(250 + 20 * Float(variant), 1, attackMs: 0.8, decayMs: 9)
                wave.addNoise(&random, cutoffHz: 700, 0.35, attackMs: 0.8, decayMs: 6)
                return HapticCue(samples: wave.finished(peak: timing.range(0.12, 0.22)),
                                 pan: timing.sign(), delayMs: timing.range(0, 2_000))
            }

        case .explosion:
            var random = HapticRandom(seed: 0xE5A1_0000)
            let s: Float = 0.8
            var wave = HapticWave(milliseconds: 420 + 800 * s)
            wave.addSine(40, 1, attackMs: 18, decayMs: 170 + 480 * s, endHz: 30)
            wave.addSine(64, 0.8, attackMs: 8, decayMs: 130 + 320 * s, endHz: 44)
            wave.addNoise(&random, cutoffHz: 120, 0.65, attackMs: 8, decayMs: 220 + 420 * s)
            wave.addSine(52, 0.5, attackMs: 6, decayMs: 110 + 150 * s, delayMs: 170)
            wave.addSine(46, 0.3, attackMs: 6, decayMs: 100 + 100 * s, delayMs: 340)
            return [HapticCue(samples: wave.finished(peak: 0.42 + 0.55 * s))]
        }
    }

    /// A single short thump, for Music Sync's beat mode on the coils.
    static func beatPunch() -> [Float] {
        var random = HapticRandom(seed: 0xBEA7_0000)
        var wave = HapticWave(milliseconds: 160)
        wave.addSine(58, 1, attackMs: 1.5, decayMs: 110, endHz: 42)
        wave.addSine(110, 0.45, attackMs: 1, decayMs: 40)
        wave.addNoise(&random, cutoffHz: 160, 0.3, attackMs: 1, decayMs: 50)
        return wave.finished(peak: 1)
    }
}

// MARK: - Filters

/// RBJ biquad, transposed direct form II.
struct Biquad {
    private var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var z1: Float = 0, z2: Float = 0

    static func lowPass(cutoff: Float, q: Float = 0.7071, sampleRate: Float = HapticWave.sampleRate) -> Biquad {
        let w = 2 * Float.pi * cutoff / sampleRate
        let alpha = sinf(w) / (2 * q)
        let c = cosf(w)
        let a0 = 1 + alpha
        return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0,
                      a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    static func highPass(cutoff: Float, q: Float = 0.7071, sampleRate: Float = HapticWave.sampleRate) -> Biquad {
        let w = 2 * Float.pi * cutoff / sampleRate
        let alpha = sinf(w) / (2 * q)
        let c = cosf(w)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0,
                      a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    /// Unity gain at `center`.
    static func bandPass(center: Float, q: Float, sampleRate: Float = HapticWave.sampleRate) -> Biquad {
        let w = 2 * Float.pi * center / sampleRate
        let alpha = sinf(w) / (2 * q)
        let c = cosf(w)
        let a0 = 1 + alpha
        return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
    }

    private init(b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    mutating func reset() { z1 = 0; z2 = 0 }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// Linear-interpolation rate conversion, carried across blocks. Plenty for
/// material that is filtered down to a few hundred hertz afterwards.
struct LinearResampler {
    private var position: Double = 0
    private var last: Float = 0

    mutating func reset() { position = 0; last = 0 }

    /// `ratio` is input rate over output rate.
    mutating func process(_ input: UnsafeBufferPointer<Float>, ratio: Double, into output: inout [Float]) {
        output.removeAll(keepingCapacity: true)
        let count = input.count
        guard count > 0, ratio.isFinite, ratio > 0 else { return }
        // Sample -1 is the previous block's last sample.
        while position <= Double(count - 1) {
            let index = Int(position.rounded(.down))
            let fraction = Float(position - Double(index))
            let a = index < 0 ? last : input[index]
            let b = index + 1 < count ? input[index + 1] : a
            output.append(a + (b - a) * fraction)
            position += ratio
        }
        position -= Double(count)
        last = input[count - 1]
    }
}

// MARK: - Mixer

/// The grips as a subwoofer: the system mix below a crossover, at the level
/// the music actually has.
public struct SubwooferSettings: Equatable {
    /// `0...1`.
    public var level: Float
    public var crossoverHz: Float
    /// Adds the octave above the deepest notes, which the coils can move.
    public var boostDeepBass: Bool

    public init(level: Float, crossoverHz: Float, boostDeepBass: Bool) {
        self.level = level
        self.crossoverHz = crossoverHz
        self.boostDeepBass = boostDeepBass
    }
}

/// What the music sends to the coils.
public enum CoilMusicStyle: Equatable {
    /// The bass line, on both grips.
    case bass
    /// Bass on the left grip, the low mids on the right.
    case fullRange
    /// A synthesised thump per beat; no audio stream.
    case beats

    init?(_ style: MusicHapticsStyle) {
        switch style {
        case .off: return nil
        case .bassKick: self = .bass
        case .fullRange: self = .fullRange
        case .beatPunch: self = .beats
        }
    }

    var streamsAudio: Bool { self != .beats }
}

/// Mixes effect voices and the music stream onto the coil channels.
///
/// `play` and the music settings are called from the main thread, the music
/// feed from the capture thread and `render` from the controller's real-time
/// thread. `render` never blocks — a contended lock yields one buffer of
/// silence — and never allocates or frees: finished voices keep their
/// samples until the main thread recycles the slot.
final class VoiceCoilMixer {
    static let leftCoilChannel = 2
    static let rightCoilChannel = 3
    static let maxVoices = 32
    static let maxFrames = 4_096

    private struct Voice {
        var samples: [Float] = []
        var position = 0
        var delay = 0
        var gainLeft: Float = 0
        var gainRight: Float = 0
        var active = false
    }

    private var voices = [Voice](repeating: Voice(), count: VoiceCoilMixer.maxVoices)
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var masterGain: Float = 0.8

    // Music.
    private let musicRing = SpeakerRingBuffer(capacity: 16_384, target: 1_024, ceiling: 4_096)
    private var musicStyle: CoilMusicStyle?
    private var musicGain: Float = 0
    private var bassStage1 = Biquad.lowPass(cutoff: 140)
    private var bassStage2 = Biquad.lowPass(cutoff: 140)
    private var lowMids = Biquad.bandPass(center: 280, q: 0.9)
    private let scratch: UnsafeMutablePointer<Float>
    private var resampler = LinearResampler()
    private var resampled: [Float] = []

    // Subwoofer. The feed runs on the capture thread and touches only the
    // producer-side fields; the filters belong to the render thread.
    private let subRing = SpeakerRingBuffer(capacity: 16_384, target: 768, ceiling: 3_072)
    private var subwoofer: SubwooferSettings?
    private var subLow1 = Biquad.lowPass(cutoff: 120)
    private var subLow2 = Biquad.lowPass(cutoff: 120)
    private var subOctaveDC = Biquad.highPass(cutoff: 25)
    private var subOctaveSmooth = Biquad.lowPass(cutoff: 240)
    private let subMono: UnsafeMutablePointer<Float>
    private static let subMonoCapacity = 16_384
    private var subResampler = LinearResampler()
    private var subResampled: [Float] = []
    /// Bass that survives a crossover is a fraction of full scale; this puts
    /// level 1 at the coils' range on loud material.
    static let subwooferDrive: Float = 2.5
    /// How much of the rectified octave is mixed back in.
    static let octaveAmount: Float = 1.2

    /// Diagnostics for `SINGLESENSE_AUDIO_LOG=1`. Written without the lock
    /// by the threads that own them; a torn read only skews a log line.
    struct Diagnostics {
        var renders = 0
        var renderedFrames = 0
        var lockMisses = 0
        var subFed = 0
        var subInPeak: Float = 0
        var coilOutPeak: Float = 0
    }
    var diagnostics = Diagnostics()
    /// The music signal is quiet once only the bass is left; this brings it
    /// to a level the coils can be felt at before the intensity ceiling.
    static let musicDrive: Float = 3

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        scratch = .allocate(capacity: Self.maxFrames * 2)
        scratch.initialize(repeating: 0, count: Self.maxFrames * 2)
        resampled.reserveCapacity(8_192)
        subMono = .allocate(capacity: Self.subMonoCapacity)
        subMono.initialize(repeating: 0, count: Self.subMonoCapacity)
        subResampled.reserveCapacity(Self.subMonoCapacity * 2)
    }

    deinit {
        lock.deallocate()
        scratch.deallocate()
        subMono.deallocate()
    }

    func setSubwoofer(_ settings: SubwooferSettings?) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if let settings {
            if settings.crossoverHz != subwoofer?.crossoverHz {
                let hz = min(max(settings.crossoverHz, 30), 400)
                subLow1 = .lowPass(cutoff: hz)
                subLow2 = .lowPass(cutoff: hz)
                subOctaveSmooth = .lowPass(cutoff: hz * 2)
            }
            if subwoofer == nil {
                subRing.reset()
                subOctaveDC.reset()
            }
        } else {
            subRing.reset()
        }
        subwoofer = settings
    }

    /// The system mix from the controller-audio tap, any channel layout.
    /// Called on the capture thread; never allocates.
    func feedSubwoofer(_ buffers: UnsafeMutableAudioBufferListPointer, sampleRate: Double) {
        os_unfair_lock_lock(lock)
        let enabled = subwoofer != nil
        os_unfair_lock_unlock(lock)
        guard enabled, let first = buffers.first, let firstData = first.mData else { return }

        let left = firstData.assumingMemoryBound(to: Float.self)
        var frames: Int
        if buffers.count >= 2, first.mNumberChannels == 1, let secondData = buffers[1].mData {
            let right = secondData.assumingMemoryBound(to: Float.self)
            frames = min(Int(first.mDataByteSize), Int(buffers[1].mDataByteSize)) / MemoryLayout<Float>.size
            frames = min(frames, Self.subMonoCapacity)
            for i in 0..<frames { subMono[i] = (left[i] + right[i]) * 0.5 }
        } else {
            let channels = max(Int(first.mNumberChannels), 1)
            frames = min(Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels, Self.subMonoCapacity)
            let rightOffset = channels > 1 ? 1 : 0
            for i in 0..<frames { subMono[i] = (left[i * channels] + left[i * channels + rightOffset]) * 0.5 }
        }
        feedSubwoofer(UnsafeBufferPointer(start: subMono, count: frames), sampleRate: sampleRate)
    }

    /// Mono at `sampleRate`; the testable half of the feed.
    func feedSubwoofer(_ mono: UnsafeBufferPointer<Float>, sampleRate: Double) {
        guard !mono.isEmpty else { return }
        diagnostics.subFed += mono.count
        for x in mono { diagnostics.subInPeak = max(diagnostics.subInPeak, abs(x)) }
        let ratio = sampleRate / Double(HapticWave.sampleRate)
        if abs(ratio - 1) < 1e-6 {
            subRing.write(frames: mono.count) { (mono[$0], mono[$0]) }
        } else {
            subResampler.process(mono, ratio: ratio, into: &subResampled)
            subResampled.withUnsafeBufferPointer { out in
                subRing.write(frames: out.count) { (out[$0], out[$0]) }
            }
        }
    }

    func setMasterGain(_ gain: Float) {
        os_unfair_lock_lock(lock)
        masterGain = gain.isFinite ? min(max(gain, 0), 1) : 0
        os_unfair_lock_unlock(lock)
    }

    /// Schedules `cues`. `pan` shifts every cue toward one grip.
    func play(_ cues: [HapticCue], pan: Float = 0, strength: Float = 1) {
        let strength = strength.isFinite ? min(max(strength, 0), 1) : 0
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        for cue in cues where !cue.samples.isEmpty {
            // Recycle a finished slot; when all are busy, the oldest-started
            // voice (furthest along) gives way.
            guard let slot = voices.firstIndex(where: { !$0.active })
                ?? voices.indices.max(by: { voices[$0].position < voices[$1].position }) else { continue }
            let p = min(max(cue.pan + pan, -1), 1)
            voices[slot] = Voice(
                samples: cue.samples,
                position: 0,
                delay: Int(max(cue.delayMs, 0) * HapticWave.sampleRate / 1000),
                gainLeft: min(1, 1 - p) * strength,
                gainRight: min(1, 1 + p) * strength,
                active: true
            )
        }
    }

    var activeVoices: Int {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return voices.reduce(0) { $0 + ($1.active ? 1 : 0) }
    }

    func clear() {
        os_unfair_lock_lock(lock)
        for i in voices.indices { voices[i].active = false }
        os_unfair_lock_unlock(lock)
    }

    func setMusic(style: CoilMusicStyle?, gain: Float) {
        os_unfair_lock_lock(lock)
        if style != musicStyle {
            bassStage1.reset(); bassStage2.reset(); lowMids.reset()
            musicRing.reset()
        }
        musicStyle = style
        musicGain = gain.isFinite ? min(max(gain, 0), 1) : 0
        os_unfair_lock_unlock(lock)
    }

    /// Mono capture at `sampleRate`, from the Music Sync tap. Ignored unless
    /// the music is streaming to the coils.
    func feedMusic(_ mono: UnsafeBufferPointer<Float>, sampleRate: Double) {
        os_unfair_lock_lock(lock)
        let streaming = musicStyle?.streamsAudio == true
        os_unfair_lock_unlock(lock)
        guard streaming, !mono.isEmpty else { return }

        let ratio = sampleRate / Double(HapticWave.sampleRate)
        if abs(ratio - 1) < 1e-6 {
            musicRing.write(frames: mono.count) { (mono[$0], mono[$0]) }
        } else {
            resampler.process(mono, ratio: ratio, into: &resampled)
            let out = resampled
            musicRing.write(frames: out.count) { (out[$0], out[$0]) }
        }
    }

    /// Fills `frames` interleaved frames of `channels` channels: the coils on
    /// channels 3-4, every other channel silent.
    func render(into out: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        out.update(repeating: 0, count: frames * channels)
        diagnostics.renders += 1
        diagnostics.renderedFrames += frames
        guard channels > Self.rightCoilChannel, frames > 0 else { return }
        guard os_unfair_lock_trylock(lock) else {
            diagnostics.lockMisses += 1
            return
        }
        defer { os_unfair_lock_unlock(lock) }

        let left = Self.leftCoilChannel
        let right = Self.rightCoilChannel

        for v in voices.indices where voices[v].active {
            var voice = voices[v]
            var frame = 0
            if voice.delay > 0 {
                let wait = min(voice.delay, frames)
                voice.delay -= wait
                frame = wait
            }
            voice.samples.withUnsafeBufferPointer { samples in
                while frame < frames, voice.position < samples.count {
                    let s = samples[voice.position] * masterGain
                    out[frame * channels + left] += s * voice.gainLeft
                    out[frame * channels + right] += s * voice.gainRight
                    voice.position += 1
                    frame += 1
                }
            }
            if voice.position >= voice.samples.count { voice.active = false }
            voices[v].position = voice.position
            voices[v].delay = voice.delay
            voices[v].active = voice.active
        }

        if let style = musicStyle, style.streamsAudio, musicGain > 0 {
            var done = 0
            while done < frames {
                let chunk = min(frames - done, Self.maxFrames)
                musicRing.read(into: scratch, frames: chunk)
                let drive = Self.musicDrive * musicGain
                for i in 0..<chunk {
                    let x = scratch[i * 2]
                    let bass = bassStage2.process(bassStage1.process(x))
                    let mids = lowMids.process(x)
                    let base = (done + i) * channels
                    switch style {
                    case .bass:
                        let s = Self.softClip(bass * drive)
                        out[base + left] += s
                        out[base + right] += s
                    case .fullRange:
                        out[base + left] += Self.softClip(bass * drive)
                        out[base + right] += Self.softClip(mids * drive)
                    case .beats:
                        break
                    }
                }
                done += chunk
            }
        }

        if let sub = subwoofer, sub.level > 0 {
            let drive = Self.subwooferDrive * sub.level
            var done = 0
            while done < frames {
                let chunk = min(frames - done, Self.maxFrames)
                subRing.read(into: scratch, frames: chunk)
                for i in 0..<chunk {
                    var bass = subLow2.process(subLow1.process(scratch[i * 2]))
                    if sub.boostDeepBass {
                        // Rectifying doubles the frequency: a 40 Hz note the
                        // coils barely move gains an 80 Hz partner they do.
                        bass += Self.octaveAmount * subOctaveSmooth.process(subOctaveDC.process(abs(bass)))
                    }
                    let s = Self.softClip(bass * drive)
                    let base = (done + i) * channels
                    out[base + left] += s
                    out[base + right] += s
                }
                done += chunk
            }
        }

        // Several voices at once must not slam the coil into its stops.
        for i in 0..<frames {
            out[i * channels + left] = Self.softClip(out[i * channels + left])
            out[i * channels + right] = Self.softClip(out[i * channels + right])
            diagnostics.coilOutPeak = max(diagnostics.coilOutPeak, abs(out[i * channels + left]))
        }
    }

    /// Untouched up to 0.8, then bending smoothly toward ±1.
    static func softClip(_ x: Float) -> Float {
        guard x.isFinite else { return 0 }
        let magnitude = abs(x)
        guard magnitude > 0.8 else { return x }
        let bent = 0.8 + 0.2 * tanhf((magnitude - 0.8) / 0.2)
        return x < 0 ? -bent : bent
    }
}

// MARK: - Engine

public enum VoiceCoilStatus: Equatable {
    /// No DualSense on USB: Bluetooth controllers cannot be reached this way.
    case unavailable
    /// The controller is there; the output opens on demand.
    case ready
    case running
    case failed(String)

    public var canPlay: Bool { self == .ready || self == .running }
}

/// Owns the controller output that carries the coil channels. It opens on
/// the first effect, or while the music streams to the coils, and closes
/// after a quiet spell so an idle app holds nothing open.
public final class VoiceCoilEngine: ObservableObject {
    public static let shared = VoiceCoilEngine()

    @Published public private(set) var status: VoiceCoilStatus = .unavailable
    /// Master strength, `0...1`.
    @Published public var strength: Double = 0.8 {
        didSet { mixer.setMasterGain(Float(strength)) }
    }

    let mixer = VoiceCoilMixer()

    private var unit: AudioUnit?
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var musicStyle: CoilMusicStyle?
    private var subwoofer: SubwooferSettings?
    private var idleStop: DispatchWorkItem?
    private var listener: AudioObjectPropertyListenerBlock?
    private static let idleTimeout: TimeInterval = 15

    private init() {
        mixer.setMasterGain(Float(strength))
        watchDeviceList()
        refreshPresence()
        if ProcessInfo.processInfo.environment["SINGLESENSE_AUDIO_LOG"] == "1" { startDiagnosticsLog() }
    }

    private var diagnosticsTimer: Timer?

    private func startDiagnosticsLog() {
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let d = self.mixer.diagnostics
            self.mixer.diagnostics = VoiceCoilMixer.Diagnostics()
            let line = "[Single Sense Coils] status=\(self.status) unit=\(self.unit != nil) music=\(String(describing: self.musicStyle)) "
                + "sub=\(self.subwoofer.map { "\($0.crossoverHz)Hz lvl \($0.level)" } ?? "off") "
                + "renders=\(d.renders) frames=\(d.renderedFrames) lockMisses=\(d.lockMisses) "
                + "subFed=\(d.subFed) subInPeak=\(d.subInPeak) coilOutPeak=\(d.coilOutPeak)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    /// Plays a preset on the coils. False when they cannot be reached, so the
    /// caller can fall back to CoreHaptics or the motors.
    @discardableResult
    public func play(_ preset: HapticPreset, pan: Float = 0) -> Bool {
        play(preset.cues(), pan: pan)
    }

    @discardableResult
    func play(_ cues: [HapticCue], pan: Float = 0) -> Bool {
        guard openIfNeeded() else { return false }
        mixer.play(cues, pan: pan)
        scheduleIdleStop()
        return true
    }

    /// One beat thump for Music Sync. Silently does nothing without coils.
    func punch(strength: Float) {
        guard status == .running else { return }
        mixer.play([HapticCue(samples: Self.punchSamples)], strength: strength)
    }

    private static let punchSamples = HapticPreset.beatPunch()

    /// Streams the music to the coils, or stops (`nil`).
    public func setMusic(style: CoilMusicStyle?, gain: Float) {
        musicStyle = style
        mixer.setMusic(style: style, gain: gain)
        if style != nil {
            idleStop?.cancel()
            _ = openIfNeeded()
        } else {
            scheduleIdleStop()
        }
    }

    /// Plays the system mix's bass on the grips, or stops (`nil`).
    public func setSubwoofer(_ settings: SubwooferSettings?) {
        subwoofer = settings
        mixer.setSubwoofer(settings)
        if settings != nil {
            idleStop?.cancel()
            _ = openIfNeeded()
        } else {
            scheduleIdleStop()
        }
    }

    /// Called from the controller-audio capture thread.
    func feedSubwoofer(_ buffers: UnsafeMutableAudioBufferListPointer, sampleRate: Double) {
        mixer.feedSubwoofer(buffers, sampleRate: sampleRate)
    }

    /// Called from the Music Sync capture thread.
    func feedMusic(_ mono: UnsafeBufferPointer<Float>, sampleRate: Double) {
        mixer.feedMusic(mono, sampleRate: sampleRate)
    }

    public func stop() {
        idleStop?.cancel()
        close()
    }

    // MARK: Device

    private func openIfNeeded() -> Bool {
        if unit != nil { return true }
        guard let device = CoreAudioQuery.dualSenseOutputDevice() else {
            status = .unavailable
            return false
        }
        switch makeControllerOutputUnit(
            device: device.id,
            sampleRate: Double(HapticWave.sampleRate),
            channels: 4,
            callback: voiceCoilRenderCallback,
            refCon: Unmanaged.passUnretained(mixer).toOpaque()
        ) {
        case .success(let newUnit):
            unit = newUnit
            deviceID = device.id
            status = .running
            print("[Single Sense Coils] Driving the voice coils on \(device.name)")
            return true
        case .failure(let message):
            status = .failed(message)
            return false
        }
    }

    private func close() {
        if let unit {
            disposeControllerOutputUnit(unit)
            self.unit = nil
        }
        deviceID = AudioObjectID(kAudioObjectUnknown)
        mixer.clear()
        refreshPresence()
    }

    private func scheduleIdleStop() {
        idleStop?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.musicStyle == nil, self.subwoofer == nil else { return }
            if self.mixer.activeVoices > 0 {
                self.scheduleIdleStop()
            } else {
                self.close()
            }
        }
        idleStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleTimeout, execute: work)
    }

    private func refreshPresence() {
        guard unit == nil else { return }
        if case .failed = status, CoreAudioQuery.dualSenseOutputDevice() != nil { return }
        status = CoreAudioQuery.dualSenseOutputDevice() == nil ? .unavailable : .ready
    }

    private func watchDeviceList() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.deviceListChanged()
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        ) == noErr {
            listener = block
        }
    }

    private func deviceListChanged() {
        let found = CoreAudioQuery.dualSenseOutputDevice()
        if unit != nil, found?.id != deviceID {
            close()
        }
        if case .failed = status, found == nil { status = .unavailable }
        refreshPresence()
        if musicStyle != nil || subwoofer != nil, found != nil { _ = openIfNeeded() }
    }
}

/// Renders the mixer on the controller's real-time thread. The mixer is
/// owned by the engine singleton, so it outlives every callback.
private let voiceCoilRenderCallback: AURenderCallback = { refCon, _, _, _, frameCount, ioData in
    guard let ioData else { return noErr }
    let mixer = Unmanaged<VoiceCoilMixer>.fromOpaque(refCon).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(ioData)
    guard let first = buffers.first, let data = first.mData else { return noErr }
    let samples = data.assumingMemoryBound(to: Float.self)
    let channels = Int(first.mNumberChannels)
    let frames = Int(frameCount)
    if channels > 0, Int(first.mDataByteSize) >= frames * channels * MemoryLayout<Float>.size {
        mixer.render(into: samples, frames: frames, channels: channels)
    } else {
        samples.update(repeating: 0, count: Int(first.mDataByteSize) / MemoryLayout<Float>.size)
    }
    return noErr
}
