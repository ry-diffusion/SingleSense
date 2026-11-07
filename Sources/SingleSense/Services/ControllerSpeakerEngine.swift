import Foundation
import Combine
import CoreAudio
import AudioToolbox
import AppKit
import os

public enum SpeakerStatus: Equatable {
    case idle
    /// No DualSense audio device. macOS only sees the controller as a sound
    /// card over USB, so this is also what Bluetooth looks like.
    case waitingForController
    case running
    /// System Audio Recording permission has not been granted.
    case permissionRequired
    case failed(String)

    public var isRunning: Bool { self == .running }
}

/// Moves the Mac's sound to the controller.
///
/// Over USB the DualSense is an ordinary four-channel sound card: channels 1-2
/// feed the headphone jack or the speaker, 3-4 the haptic actuators. Simply
/// making it the default output would put only the right channel on the
/// (mono) speaker, and would hand haptics whatever macOS chose to send there.
///
/// So instead a process tap takes the whole system mix — muting it on the
/// Mac while it is being read — and an output unit bound to the controller
/// plays it back on channels 1-2 only, folded to mono for the speaker or left
/// in stereo when something is plugged into the jack. The tap leaves this
/// process out, otherwise it would capture, and mute, its own playback.
public final class ControllerSpeakerEngine: ObservableObject {
    public static let shared = ControllerSpeakerEngine()

    @Published public private(set) var status: SpeakerStatus = .idle
    @Published public private(set) var deviceName: String?

    private let ring = SpeakerRingBuffer()
    private var wantsOutput = false
    private var gain: Float = 0.64
    private var stereo = false

    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var outputUnit: AudioUnit?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var deviceListListener: AudioObjectPropertyListenerBlock?

    private init() {}

    // MARK: - Control (main thread)

    /// Starts or stops playback to match `active`. Safe to call repeatedly.
    public func setActive(_ active: Bool) {
        wantsOutput = active
        if active { watchDeviceList() }
        reconcile()
    }

    /// Linear output gain, `0...1`.
    public func setGain(_ newGain: Float) {
        gain = newGain.isFinite ? min(max(newGain, 0), 1) : 0
        ring.setParameters(gain: gain, mono: !stereo)
    }

    /// Stereo for the headphone jack; the speaker gets a mono fold-down.
    public func setStereo(_ newStereo: Bool) {
        stereo = newStereo
        ring.setParameters(gain: gain, mono: !stereo)
    }

    /// Tries again after the user has dealt with a permission or a cable.
    public func retry() {
        stop()
        status = .idle
        reconcile()
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Brings the running state in line with what is wanted and what is
    /// plugged in. Runs on every device-list change.
    private func reconcile() {
        guard wantsOutput else {
            stop()
            status = .idle
            return
        }

        let found = CoreAudioQuery.dualSenseOutputDevice()
        if outputDeviceID != kAudioObjectUnknown {
            // Our own aggregate device coming and going lands here too.
            if found?.id == outputDeviceID { return }
            stop()
        }

        guard let device = found else {
            status = .waitingForController
            deviceName = nil
            return
        }
        // A failure stays put until something changes; retrying on every
        // device-list notification would only repeat it.
        if case .failed = status, deviceName == device.name { return }
        if status == .permissionRequired, deviceName == device.name { return }
        start(device: device)
    }

    private func watchDeviceList() {
        guard deviceListListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.reconcile()
        }
        let result = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        if result == noErr { deviceListListener = listener }
    }

    // MARK: - Start / stop

    private func start(device: (id: AudioObjectID, name: String)) {
        deviceName = device.name
        ring.reset()
        ring.setParameters(gain: gain, mono: !stereo)

        // Without excluding ourselves the tap would swallow the very audio
        // this engine plays, leaving the controller silent.
        guard let ownProcess = CoreAudioQuery.currentProcessObject() else {
            status = .failed("Core Audio does not list Single Sense as a client yet. Try again in a moment.")
            return
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        tapDescription.name = "Single Sense Controller Speaker"
        tapDescription.isPrivate = true
        // Silences the Mac only while the tap is actually being read, so a
        // stall or a crash cannot leave the system muted.
        tapDescription.muteBehavior = .mutedWhenTapped

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr else {
            status = Self.isPermissionError(tapStatus)
                ? .permissionRequired
                : .failed("Could not tap the system audio (code \(tapStatus))")
            return
        }
        tapID = newTapID

        let sampleRate = CoreAudioQuery.tapSampleRate(newTapID) ?? 48_000

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SingleSenseSpeakerTap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregateID)
        guard aggregateStatus == noErr else {
            stop()
            status = .failed("Could not create the capture device (code \(aggregateStatus))")
            return
        }
        aggregateDeviceID = newAggregateID

        switch makeOutputUnit(device: device.id, sampleRate: sampleRate) {
        case .success(let unit):
            outputUnit = unit
            outputDeviceID = device.id
        case .failure(let message):
            stop()
            status = .failed(message)
            return
        }

        let ring = self.ring
        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProcID, newAggregateID, nil) { _, input, _, _, _ in
            ring.write(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)))
        }
        guard procStatus == noErr, let validProcID = newProcID else {
            stop()
            status = .failed("Could not read the system audio (code \(procStatus))")
            return
        }
        procID = validProcID

        let startStatus = AudioDeviceStart(newAggregateID, validProcID)
        guard startStatus == noErr else {
            stop()
            status = Self.isPermissionError(startStatus)
                ? .permissionRequired
                : .failed("The system audio tap was refused (code \(startStatus))")
            return
        }

        status = .running
        print("[Single Sense Speaker] Playing system audio on \(device.name) at \(Int(sampleRate)) Hz")
    }

    /// Tears down whatever exists, tap first so the Mac is unmuted before the
    /// controller goes quiet. Idempotent.
    private func stop() {
        if let procID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        procID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        if let unit = outputUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            outputUnit = nil
        }
        outputDeviceID = AudioObjectID(kAudioObjectUnknown)
        ring.reset()
        if status == .running { status = .idle }
    }

    private enum UnitResult {
        case success(AudioUnit)
        case failure(String)
    }

    /// An output-only HAL unit on the controller. Output-only matters: the
    /// controller also has a microphone, and opening it would raise the
    /// microphone indicator and a permission prompt for nothing.
    private func makeOutputUnit(device: AudioObjectID, sampleRate: Double) -> UnitResult {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            return .failure("The system output unit is unavailable")
        }
        var maybeUnit: AudioUnit?
        guard AudioComponentInstanceNew(component, &maybeUnit) == noErr, let unit = maybeUnit else {
            return .failure("Could not create the controller output")
        }

        func fail(_ what: String, _ status: OSStatus) -> UnitResult {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            return .failure("\(what) (code \(status))")
        }

        var disable: UInt32 = 0
        var enable: UInt32 = 1
        let uint32Size = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disable, uint32Size)
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, uint32Size)

        var deviceID = device
        var status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else { return fail("Could not open the controller as a sound device", status) }

        // Interleaved stereo float at the tap's rate; the unit converts to
        // whatever the controller runs at and fills channels 1-2, leaving
        // the haptic channels silent.
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
            &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else { return fail("The controller refused the audio format", status) }

        var callback = AURenderCallbackStruct(
            inputProc: speakerRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(ring).toOpaque()
        )
        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
            &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else { return fail("Could not attach the playback callback", status) }

        status = AudioUnitInitialize(unit)
        guard status == noErr else { return fail("Could not prepare the controller output", status) }
        status = AudioOutputUnitStart(unit)
        guard status == noErr else { return fail("Could not start the controller output", status) }
        return .success(unit)
    }

    private static func isPermissionError(_ status: OSStatus) -> Bool {
        status == 1852797029 /* 'nope' */ || status == -50
    }
}

/// Pulls from the ring buffer on the controller's real-time render thread.
/// The ring is owned by the engine singleton, so the unretained reference
/// outlives every callback.
private let speakerRenderCallback: AURenderCallback = { refCon, _, _, _, frameCount, ioData in
    guard let ioData else { return noErr }
    let ring = Unmanaged<SpeakerRingBuffer>.fromOpaque(refCon).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(ioData)
    guard let first = buffers.first, let data = first.mData else { return noErr }
    let samples = data.assumingMemoryBound(to: Float.self)
    let frames = Int(frameCount)
    if first.mNumberChannels == 2, Int(first.mDataByteSize) >= frames * 8 {
        ring.read(into: samples, frames: frames)
    } else {
        samples.update(repeating: 0, count: Int(first.mDataByteSize) / MemoryLayout<Float>.size)
    }
    return noErr
}

// MARK: - Ring buffer

/// Stereo FIFO between the tap's I/O thread and the controller's render
/// thread, which run on two unrelated clocks.
///
/// Playback waits until `target` frames are queued, so ordinary jitter
/// between the two callbacks never starves the output. Slow clock drift is
/// absorbed the blunt way: an overfull buffer drops back to `target`, an empty
/// one goes quiet and refills. Either happens at most every few minutes.
final class SpeakerRingBuffer {
    let capacity: Int
    let target: Int
    let ceiling: Int

    private let storage: UnsafeMutablePointer<Float>
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var readFrame = 0
    private var count = 0
    private var primed = false
    private var gain: Float = 1
    private var mono = true

    init(capacity: Int = 16_384, target: Int = 2_048, ceiling: Int = 6_144) {
        self.capacity = capacity
        self.target = min(target, capacity)
        self.ceiling = min(max(ceiling, target), capacity)
        storage = .allocate(capacity: capacity * 2)
        storage.initialize(repeating: 0, count: capacity * 2)
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deallocate()
        lock.deallocate()
    }

    var bufferedFrames: Int {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return count
    }

    func setParameters(gain: Float, mono: Bool) {
        os_unfair_lock_lock(lock)
        self.gain = gain
        self.mono = mono
        os_unfair_lock_unlock(lock)
    }

    func reset() {
        os_unfair_lock_lock(lock)
        readFrame = 0
        count = 0
        primed = false
        os_unfair_lock_unlock(lock)
    }

    /// Accepts the tap's buffers, interleaved or one buffer per channel.
    /// Anything beyond two channels is ignored; mono is duplicated.
    func write(_ buffers: UnsafeMutableAudioBufferListPointer) {
        guard let first = buffers.first, let firstData = first.mData else { return }
        let left = firstData.assumingMemoryBound(to: Float.self)

        if buffers.count >= 2, first.mNumberChannels == 1,
           let secondData = buffers[1].mData {
            let right = secondData.assumingMemoryBound(to: Float.self)
            let frames = min(Int(first.mDataByteSize), Int(buffers[1].mDataByteSize)) / MemoryLayout<Float>.size
            write(frames: frames) { (left[$0], right[$0]) }
        } else {
            let channels = max(Int(first.mNumberChannels), 1)
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
            let rightOffset = channels > 1 ? 1 : 0
            write(frames: frames) { (left[$0 * channels], left[$0 * channels + rightOffset]) }
        }
    }

    func write(frames: Int, sample: (Int) -> (Float, Float)) {
        guard frames > 0 else { return }
        os_unfair_lock_lock(lock)
        for i in 0..<frames {
            if count == capacity {
                readFrame = (readFrame + 1) % capacity
                count -= 1
            }
            let slot = (readFrame + count) % capacity
            let (l, r) = sample(i)
            storage[slot * 2] = l.isFinite ? l : 0
            storage[slot * 2 + 1] = r.isFinite ? r : 0
            count += 1
        }
        if count > ceiling {
            let excess = count - target
            readFrame = (readFrame + excess) % capacity
            count = target
        }
        os_unfair_lock_unlock(lock)
    }

    /// Fills `frames` interleaved stereo frames, padding with silence.
    func read(into out: UnsafeMutablePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }

        if !primed {
            guard count >= target else {
                out.update(repeating: 0, count: frames * 2)
                return
            }
            primed = true
        }

        let available = min(frames, count)
        for i in 0..<available {
            let slot = (readFrame + i) % capacity
            var l = storage[slot * 2]
            var r = storage[slot * 2 + 1]
            if mono {
                let m = (l + r) * 0.5
                l = m
                r = m
            }
            out[i * 2] = l * gain
            out[i * 2 + 1] = r * gain
        }
        readFrame = (readFrame + available) % capacity
        count -= available

        if available < frames {
            (out + available * 2).update(repeating: 0, count: (frames - available) * 2)
            primed = false
        }
    }
}

// MARK: - Core Audio lookups

enum CoreAudioQuery {
    private static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The `AudioObjectID` Core Audio uses for this process, which is what a
    /// tap's exclusion list wants.
    static func currentProcessObject() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }

    static func tapSampleRate(_ tap: AudioObjectID) -> Double? {
        var addr = address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &format) == noErr,
              format.mSampleRate.isFinite, format.mSampleRate > 0 else { return nil }
        return format.mSampleRate
    }

    static func deviceIDs() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func outputStreamCount(_ device: AudioObjectID) -> Int {
        var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    /// The controller's USB audio interface, if one is attached.
    static func dualSenseOutputDevice() -> (id: AudioObjectID, name: String)? {
        for device in deviceIDs() where outputStreamCount(device) > 0 {
            let name = string(device, kAudioObjectPropertyName) ?? ""
            let model = string(device, kAudioDevicePropertyModelUID) ?? ""
            if isDualSense(name: name, modelUID: model) {
                return (device, name.isEmpty ? "DualSense" : name)
            }
        }
        return nil
    }

    /// Matches by name, or by Sony's vendor ID plus a DualSense product ID in
    /// the model UID, for a controller someone renamed in Audio MIDI Setup.
    /// The vendor ID alone would also catch Sony headsets.
    static func isDualSense(name: String, modelUID: String) -> Bool {
        if name.localizedCaseInsensitiveContains("dualsense") { return true }
        let model = modelUID.lowercased()
        let productIDs = [HIDDriver.dualSenseProductID, HIDDriver.dualSenseEdgeProductID]
            .map { String(format: "%04x", $0) }
        return model.contains(String(format: "%04x", HIDDriver.sonyVendorID))
            && productIDs.contains(where: model.contains)
    }
}
