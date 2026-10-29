import CoreAudio
import AudioToolbox
import os

/// Reads HAL properties without changing the user's default audio device.
@available(macOS 14.2, *)
enum MixerHAL {
    struct Failure: LocalizedError {
        let operation: String
        let status: OSStatus
        var errorDescription: String? { "\(operation): \(status)" }
    }
    static func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw Failure(operation: operation, status: status) }
    }
    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer), "Read audio property")
        }
        return value
    }
    static func list(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "List audio sources")
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        if size > 0 {
            try values.withUnsafeMutableBytes { bytes in
                try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!), "Read audio sources")
            }
        }
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
    static func defaultOutput() throws -> AudioObjectID {
        try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0))
    }
}

/// One private aggregate per source. Muting starts only while its IO proc runs;
/// stopping or destroying it restores the source's original route.
@available(macOS 14.2, *)
final class AudioMixerRoute {
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private let gain = MixerGain()
    let output: AudioObjectID
    private let sampleRate: Double

    init(process: AudioObjectID, output: AudioObjectID, volume: Float) throws {
        self.output = output
        let streams = try MixerHAL.list(output, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        let inputs = try MixerHAL.list(output, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        // Fail before muting for unsupported routes. No microphone is opened.
        guard streams.count == 1, inputs.isEmpty else {
            throw MixerHAL.Failure(operation: String(localized: "Choose a stereo output without microphone input for the mixer."), status: kAudioHardwareUnsupportedOperationError)
        }
        let format = try MixerHAL.read(streams[0], kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
        guard Self.supports(format) else {
            throw MixerHAL.Failure(operation: String(localized: "This audio output format is not supported by the mixer."), status: kAudioHardwareUnsupportedOperationError)
        }
        sampleRate = format.mSampleRate
        gain.set(volume)
        do {
            let uid: CFString = try MixerHAL.read(output, kAudioDevicePropertyDeviceUID, initial: "" as CFString)
            let description = CATapDescription(processes: [process], deviceUID: uid as String, stream: 0)
            description.name = "NotchFlow Mixer"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try MixerHAL.check(AudioHardwareCreateProcessTap(description, &tap), "Create audio tap")
            let tapFormat = try MixerHAL.read(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            guard Self.supports(tapFormat), tapFormat.mSampleRate == sampleRate else {
                throw MixerHAL.Failure(operation: "Incompatible audio tap format", status: kAudioHardwareUnsupportedOperationError)
            }
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "NotchFlow Mixer",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                 kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try MixerHAL.check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &device), "Create mixer output")
            let inputStreams = try MixerHAL.list(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            let outputStreams = try MixerHAL.list(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            guard inputStreams.count == 1, outputStreams.count == 1 else {
                throw MixerHAL.Failure(operation: "Incompatible mixer streams", status: kAudioHardwareUnsupportedOperationError)
            }
            for stream in inputStreams + outputStreams {
                let actual = try MixerHAL.read(stream, kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())
                guard Self.supports(actual), actual.mSampleRate == sampleRate else {
                    throw MixerHAL.Failure(operation: "Incompatible mixer format", status: kAudioHardwareUnsupportedOperationError)
                }
            }
            let gain = self.gain
            try MixerHAL.check(AudioDeviceCreateIOProcIDWithBlock(&io, device, nil) { _, input, _, output, _ in
                // Never block the audio thread waiting for a slider update.
                let level = gain.readForAudioThread()
                MixerSamples.copy(input: input, output: output, gain: level)
            }, "Create mixer callback")
            try MixerHAL.check(AudioDeviceStart(device, io), "Start audio mixer")
        } catch {
            stop()
            throw error
        }
    }

    static func supports(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32 &&
        format.mFormatFlags & kAudioFormatFlagIsFloat != 0 &&
        format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 &&
        format.mFormatFlags & kAudioFormatFlagIsPacked != 0 && format.mChannelsPerFrame == 2
    }
    func setVolume(_ value: Float) { gain.set(value) }
    func isOutputCurrent() -> Bool {
        guard let current = try? MixerHAL.defaultOutput(), current == output,
              let rate = try? MixerHAL.read(output, kAudioDevicePropertyNominalSampleRate, initial: Double(0)) else { return false }
        return rate == sampleRate
    }
    func stop() {
        if let io {
            AudioDeviceStop(device, io)
            AudioDeviceDestroyIOProcID(device, io)
            self.io = nil
        }
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { stop() }
}

/// Float32 stereo conversion, including planar/interleaved layouts. No allocation
/// or HAL calls on the realtime thread. Extra output frames are always cleared.
enum MixerSamples {
    static func copy(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let sources = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let destinations = UnsafeMutableAudioBufferListPointer(output)
        for buffer in destinations {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard sources.reduce(0, { $0 + $1.mNumberChannels }) == 2,
              destinations.reduce(0, { $0 + $1.mNumberChannels }) == 2 else { return }
        let level = gain.isFinite ? min(1, max(0, gain)) : 1
        for channel in 0..<2 {
            let source = sources[sources.count == 1 ? 0 : channel]
            let destination = destinations[destinations.count == 1 ? 0 : channel]
            guard let src = source.mData?.assumingMemoryBound(to: Float.self),
                  let dst = destination.mData?.assumingMemoryBound(to: Float.self),
                  source.mNumberChannels > 0, destination.mNumberChannels > 0 else { continue }
            let sourceStride = Int(source.mNumberChannels), destinationStride = Int(destination.mNumberChannels)
            let frames = min(Int(source.mDataByteSize) / 4 / sourceStride, Int(destination.mDataByteSize) / 4 / destinationStride)
            for frame in 0..<frames {
                dst[frame * destinationStride + (destinationStride == 1 ? 0 : channel)] =
                    src[frame * sourceStride + (sourceStride == 1 ? 0 : channel)] * level
            }
        }
    }
}

/// Only the IO callback accesses previous; UI changes only the locked value.
private final class MixerGain: @unchecked Sendable {
    private let value = OSAllocatedUnfairLock(initialState: Float(1))
    private var previous: Float = 1
    func set(_ level: Float) { value.withLock { $0 = level.isFinite ? min(1, max(0, level)) : 1 } }
    func readForAudioThread() -> Float {
        if let current = value.withLockIfAvailable({ $0 }) { previous = current }
        return previous
    }
}
