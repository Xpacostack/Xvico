// Adapted from SiriRemoteVibe app/NativePushToTalk.swift (GPL-3.0).
// Source and license: ThirdParty/SiriRemoteVoiceBridge/SOURCE.md / LICENSE.
import Foundation
import IOKit
import IOKit.hid

enum RemoteMicrophoneControl {
    static func setEnabled(_ enabled: Bool) -> IOReturn {
        guard let matching = IOServiceMatching("AppleEmbeddedBluetoothDeviceManagement") else { return kIOReturnNotFound }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return kIOReturnNotFound }
        defer { IOObjectRelease(iterator) }
        var result = kIOReturnNotFound
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
            let product = IORegistryEntrySearchCFProperty(service, kIOServicePlane, kIOHIDProductIDKey as CFString, nil, options) as? NSNumber
            let vendor = IORegistryEntrySearchCFProperty(service, kIOServicePlane, kIOHIDVendorIDKey as CFString, nil, options) as? NSNumber
            guard product?.intValue == 0x0315, vendor?.intValue == 0x004c else { continue }
            result = IORegistryEntrySetCFProperties(service, ["PushToTalk": NSNumber(value: UInt8(enabled ? 1 : 0))] as CFDictionary)
            if result == kIOReturnSuccess { return result }
        }
        return result
    }
}

@main
enum MicrophoneControlMain {
    static func main() {
        guard CommandLine.arguments.count == 2,
              ["enable", "disable"].contains(CommandLine.arguments[1]) else { exit(2) }
        let result = RemoteMicrophoneControl.setEnabled(CommandLine.arguments[1] == "enable")
        print(String(format: "%08X", UInt32(bitPattern: result)))
    }
}
