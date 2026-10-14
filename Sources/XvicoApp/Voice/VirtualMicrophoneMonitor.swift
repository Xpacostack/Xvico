import AVFoundation
import AudioToolbox
import CoreAudio
import Combine

// AUHAL binds the input device before initialization. AVAudioEngine's input node
// can retain the default device's format after CurrentDevice is changed.
private final class VirtualInputMeter: @unchecked Sendable {
    var unit: AudioUnit?
    private let lock = NSLock()
    private var maximum: Float = 0
    private var renderError: OSStatus = noErr
    func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                _ time: UnsafePointer<AudioTimeStamp>, _ frames: UInt32) -> OSStatus {
        guard let unit else { return noErr }
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: Int(frames))
        defer { samples.deallocate() }
        var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 1, mDataByteSize: frames * 4, mData: samples))
        let result = AudioUnitRender(unit, flags, time, 1, frames, &buffers)
        var value: Float = 0
        if result == noErr {
            for i in 0..<Int(frames) { value = max(value, abs(samples[i])) }
        }
        lock.lock(); maximum = max(maximum, value)
        if result != noErr { renderError = result }; lock.unlock()
        return result
    }
    func reading() -> (Float, OSStatus) {
        lock.lock(); defer { lock.unlock() }; return (maximum, renderError)
    }
}

@MainActor final class VirtualMicrophoneMonitor: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var status = "尚未检测虚拟麦克风"
    @Published private(set) var peak: Float = 0
    private var meter: VirtualInputMeter?
    private var timeout: Task<Void, Never>?

    private func device() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "XvibeMicrophone_UID" as CFString
        var result = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &uid) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), $0, &size, &result)
        }
        return status == noErr && result != 0 ? result : nil
    }
    func start() {
        stop(); peak = 0
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            status = "请先在设备设置授予麦克风权限"; return
        }
        guard var id = device() else { status = "系统未找到 Xvico Microphone"; return }
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            status = "系统未提供 AUHAL 输入组件"; return
        }
        var instance: AudioUnit?
        var result = AudioComponentInstanceNew(component, &instance)
        guard result == noErr, let unit = instance else { status = "无法创建虚拟输入：\(result)"; return }
        let meter = VirtualInputMeter(); meter.unit = unit
        var enabled: UInt32 = 1; var disabled: UInt32 = 0
        result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, 4)
        if result == noErr { result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, 4) }
        if result == noErr { result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, 4) }
        var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: 4, mFramesPerPacket: 1,
            mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        if result == noErr { result = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, UInt32(MemoryLayout.size(ofValue: format))) }
        var callback = AURenderCallbackStruct(inputProc: { context, flags, time, _, frames, _ in
            Unmanaged<VirtualInputMeter>.fromOpaque(context).takeUnretainedValue().render(flags, time, frames)
        }, inputProcRefCon: Unmanaged.passUnretained(meter).toOpaque())
        if result == noErr { result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout.size(ofValue: callback))) }
        if result == noErr { result = AudioUnitInitialize(unit) }
        if result == noErr { result = AudioOutputUnitStart(unit) }
        guard result == noErr else {
            AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit)
            status = "虚拟输入启动失败：\(result)"; return
        }
        self.meter = meter; running = true; status = "正在检测系统虚拟输入，最多 10 秒"
        timeout = Task { [weak self] in
            for _ in 0..<100 {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self else { return }
                let (value, error) = meter.reading(); self.peak = value
                if error != noErr {
                    self.stop(); self.status = "虚拟输入读取失败：\(error)"; return
                }
                self.status = value > 0.0001 ? "已从系统 Xvico Microphone 读到非静音信号" : "虚拟输入已打开，等待非静音信号"
            }
            guard let self else { return }
            self.stop()
            self.status = self.peak > 0.0001 ? "检测完成：系统虚拟输入有非静音信号" : "检测完成：系统虚拟输入仍为静音"
        }
    }
    func stop() {
        timeout?.cancel(); timeout = nil
        if let unit = meter?.unit {
            AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit)
        }
        meter = nil; running = false
    }
}
