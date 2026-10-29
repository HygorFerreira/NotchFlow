import AudioToolbox

@main
struct AudioMixerTests {
    static func main() {
        // Exercise all four planar/interleaved combinations, mute, attenuation,
        // clipping of gain, and zero padding when output is longer than input.
        for inputPlanar in [false, true] {
            for outputPlanar in [false, true] {
                for gain: Float in [0, 0.25, 1, -1, 2, .nan] {
                    let input = make(planar: inputPlanar, frames: 2)
                    let output = make(planar: outputPlanar, frames: 3)
                    defer { free(input); free(output) }
                    for channel in 0..<2 {
                        for frame in 0..<2 { set(input, channel, frame, Float((channel + 1) * (frame + 1))) }
                    }
                    MixerSamples.copy(input: UnsafePointer(input.unsafeMutablePointer), output: output.unsafeMutablePointer, gain: gain)
                    let expected: Float = gain.isFinite ? min(1, max(0, gain)) : 1
                    for channel in 0..<2 {
                        for frame in 0..<2 {
                            precondition(get(output, channel, frame) == Float((channel + 1) * (frame + 1)) * expected)
                        }
                        precondition(get(output, channel, 2) == 0)
                    }
                }
            }
        }
        if #available(macOS 14.2, *) {
            var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8,
                mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
            precondition(AudioMixerRoute.supports(format))
            format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
            precondition(!AudioMixerRoute.supports(format))
            format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            format.mChannelsPerFrame = 6
            precondition(!AudioMixerRoute.supports(format))
        }
        print("Audio mixer: 24 buffer/gain scenarios and format validation passed")
    }
    static func make(planar: Bool, frames: Int) -> UnsafeMutableAudioBufferListPointer {
        let list = AudioBufferList.allocate(maximumBuffers: planar ? 2 : 1)
        for index in list.indices {
            let channels = planar ? 1 : 2
            let data = UnsafeMutablePointer<Float>.allocate(capacity: frames * channels)
            data.initialize(repeating: 99, count: frames * channels)
            list[index] = AudioBuffer(mNumberChannels: UInt32(channels), mDataByteSize: UInt32(frames * channels * 4), mData: data)
        }
        return list
    }
    static func set(_ list: UnsafeMutableAudioBufferListPointer, _ channel: Int, _ frame: Int, _ value: Float) {
        let buffer = list[list.count == 1 ? 0 : channel]
        buffer.mData!.assumingMemoryBound(to: Float.self)[frame * Int(buffer.mNumberChannels) + (list.count == 1 ? channel : 0)] = value
    }
    static func get(_ list: UnsafeMutableAudioBufferListPointer, _ channel: Int, _ frame: Int) -> Float {
        let buffer = list[list.count == 1 ? 0 : channel]
        return buffer.mData!.assumingMemoryBound(to: Float.self)[frame * Int(buffer.mNumberChannels) + (list.count == 1 ? channel : 0)]
    }
    static func free(_ list: UnsafeMutableAudioBufferListPointer) {
        for buffer in list { buffer.mData!.assumingMemoryBound(to: Float.self).deallocate() }
        list.unsafeMutablePointer.deallocate()
    }
}
