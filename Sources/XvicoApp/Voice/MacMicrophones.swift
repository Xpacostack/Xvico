import CoreAudio
import Foundation

enum MacMicrophones {
    struct Device { let id: AudioDeviceID; let name: String }
    static func inputs() throws -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var stream = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamsSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &stream, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let name = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
            name.initialize(to: nil)
            defer { name.deinitialize(count: 1); name.deallocate() }
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, name) == noErr, let value = name.pointee else { return nil }
            return Device(id: id, name: value as String)
        }
    }
    static func switchInput(_ direction: Int) throws -> String {
        let devices = try inputs()
        guard !devices.isEmpty else { throw NSError(domain: "Xvico.Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可用的系统输入麦克风"]) }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &current) == noErr else { throw failure() }
        let index = devices.firstIndex { $0.id == current } ?? 0
        let next = devices[(index + direction + devices.count) % devices.count]
        var id = next.id
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id) == noErr else { throw failure() }
        return next.name
    }
    static func selectVirtualInput() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uid: CFString = "XvibeMicrophone_UID" as CFString
        var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let result = withUnsafePointer(to: &uid) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        guard result == noErr, id != 0 else {
            throw NSError(domain: "Xvico.Audio", code: 3, userInfo: [NSLocalizedDescriptionKey: "尚未安装 Xvico Microphone"])
        }
        address.mSelector = kAudioHardwarePropertyDefaultInputDevice
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id) == noErr else { throw failure() }
        var actual = AudioDeviceID(0)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &actual) == noErr, actual == id else { throw failure() }
        return (try? inputs().first { $0.id == id }?.name) ?? "Xvico Microphone"
    }
    private static func failure() -> NSError { NSError(domain: "Xvico.Audio", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法切换系统输入麦克风"]) }
}
