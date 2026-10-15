import CoreFoundation
import Foundation
import IOKit.hid

// Consumer Control (0x0c/1) and Digitizer (0x0d/1) use separate managers.
enum RemoteHIDInterface: CaseIterable {
    case buttons, touch
    var page: Int { self == .buttons ? 0x0c : 0x0d }
    static let vendorID = 0x004c
    static let productID = 0x0315
    var matching: [String: Any] {
        [kIOHIDVendorIDKey as String: Self.vendorID,
         kIOHIDProductIDKey as String: Self.productID,
         kIOHIDPrimaryUsagePageKey as String: page,
         kIOHIDPrimaryUsageKey as String: 1]
    }
    static func identify(vendor: Int, product: Int, page: Int, usage: Int) -> Self? {
        guard vendor == vendorID, product == productID, usage == 1 else { return nil }
        return allCases.first { $0.page == page }
    }
}

struct RemotePowerSuppression {
    var buttonInterfacePresent = false
    var buttonManagerOpenWasSeized = false
    var active: Bool { buttonInterfacePresent && buttonManagerOpenWasSeized }
}

// dispatch. Packed HID reports may repeat unchanged releases for other keys.
struct RemoteButtonValueFilter {
    private var values: [Int: [String: Int]] = [:]
    mutating func changed(deviceID: Int, page: Int, usage: Int, value: Int) -> Bool {
        let key = "\(page):\(usage)"
        guard (values[deviceID]?[key] ?? 0) != value else { return false }
        values[deviceID, default: [:]][key] = value
        return true
    }
    mutating func remove(deviceID: Int) { values.removeValue(forKey: deviceID) }
}

@MainActor
protocol RemoteInputMonitoring: AnyObject {
    var onUsage: ((Int, Int, Bool) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    var onTouch: ((RemoteTouchSample) -> Void)? { get set }
    var onTouchStatus: ((String) -> Void)? { get set }
    var onInterception: ((Bool) -> Void)? { get set }
    var onDiagnostic: ((String) -> Void)? { get set }
    var onInterceptionDetail: ((String?) -> Void)? { get set }
    var onInputLost: (() -> Void)? { get set }
    func start(interceptButtons: Bool)
    func stop()
    func setButtonInterception(_ enabled: Bool)
    func reidentifyTouch()
}

@MainActor
final class RemoteInputMonitor: RemoteInputMonitoring {
    var onUsage: ((Int, Int, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    var onTouch: ((RemoteTouchSample) -> Void)?
    var onTouchStatus: ((String) -> Void)?
    var onInterception: ((Bool) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onInterceptionDetail: ((String?) -> Void)?
    var onInputLost: (() -> Void)?
    private var managers: [RemoteHIDInterface: IOHIDManager] = [:]
    private final class CallbackContext {
        weak var monitor: RemoteInputMonitor?
        let kind: RemoteHIDInterface
        init(_ monitor: RemoteInputMonitor, kind: RemoteHIDInterface) {
            self.monitor = monitor; self.kind = kind
        }
    }
    private var callbackContexts: [RemoteHIDInterface: CallbackContext] = [:]
    private var remoteDevices: [Int: RemoteHIDInterface] = [:]
    private var interceptButtons = true
    private let multitouch: any RemoteMultitouchMonitoring
    private let touchReconnect: RemoteTouchReconnectController
    private var suppression = RemotePowerSuppression()
    private var touches: [Int: RemoteTouchSample] = [:]
    private var coordinateAxes: [Int: Set<Int>] = [:]
    private var buttonValues = RemoteButtonValueFilter()

    init(multitouch: (any RemoteMultitouchMonitoring)? = nil) {
        let driver = multitouch ?? RemoteMultitouchMonitor()
        self.multitouch = driver
        touchReconnect = RemoteTouchReconnectController(driver: driver)
    }

    func start(interceptButtons: Bool = true) {
        guard managers.isEmpty else { return }
        self.interceptButtons = interceptButtons
        multitouch.onSample = { [weak self] in self?.onTouch?($0) }
        multitouch.onStatus = { [weak self] in self?.onTouchStatus?($0) }
        open(.touch)
        open(.buttons)
    }

    func setButtonInterception(_ enabled: Bool) {
        interceptButtons = enabled
        guard managers[.buttons] != nil else { return }
        close(.buttons)
        open(.buttons)
    }

    func reidentifyTouch() {
        guard managers[.touch] != nil else { return }
        close(.touch)
        open(.touch)
    }

    private func open(_ kind: RemoteHIDInterface) {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let registration = CallbackContext(self, kind: kind)
        callbackContexts[kind] = registration
        IOHIDManagerSetDeviceMatching(manager, kind.matching as CFDictionary)
        let context = Unmanaged.passUnretained(registration).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, sender, device in
            guard let context, let sender else { return }
            let registration = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                guard let monitor = registration.monitor,
                      monitor.callbackContexts[registration.kind] === registration,
                      monitor.isCurrentManager(sender) else { return }
                monitor.didMatch(device)
            }
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let registration = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
            // Input callback sender is the IOHIDDevice, not the IOHIDManager.
            // didReceive checks the element's device against the matched set.
            Task { @MainActor in
                guard let monitor = registration.monitor,
                      monitor.callbackContexts[registration.kind] === registration else { return }
                monitor.didReceive(value)
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, sender, device in
            guard let context, let sender else { return }
            let registration = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                guard let monitor = registration.monitor,
                      monitor.callbackContexts[registration.kind] === registration,
                      monitor.isCurrentManager(sender) else { return }
                monitor.didRemove(device)
            }
        }, context)
        managers[kind] = manager
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let requestedSeize = kind == .buttons && interceptButtons
        let options = IOOptionBits(requestedSeize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone)
        let result = IOHIDManagerOpen(manager, options)
        if kind == .buttons {
            suppression.buttonManagerOpenWasSeized = requestedSeize && result == kIOReturnSuccess
            onInterceptionDetail?(nil)
        }
        if result != kIOReturnSuccess {
            if requestedSeize {
                let fallback = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
                onInterceptionDetail?("独占打开失败（\(result)）；\(fallback == kIOReturnSuccess ? "已退回普通监听" : "普通监听也未开启")。")
                if fallback != kIOReturnSuccess { onStatus?("无法启用遥控器按键监听（\(fallback)）") }
            } else if kind == .buttons { onStatus?("无法启用遥控器按键监听（\(result)）") }
            else { onTouchStatus?("无法启用遥控器触控监听（\(result)）") }
        }
        onInterception?(suppression.active)
    }

    private func isCurrentManager(_ sender: UnsafeMutableRawPointer) -> Bool {
        managers.values.contains { Unmanaged.passUnretained($0).toOpaque() == sender }
    }

    private func close(_ kind: RemoteHIDInterface) {
        guard let manager = managers.removeValue(forKey: kind) else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        callbackContexts.removeValue(forKey: kind)
        let removed = remoteDevices.filter { $0.value == kind }.map(\.key)
        for id in removed { remoteDevices.removeValue(forKey: id); touches.removeValue(forKey: id); coordinateAxes.removeValue(forKey: id); buttonValues.remove(deviceID: id) }
        // Reopening an interface (for example after changing interception)
        // also loses matching releases from the old input stream.
        if !removed.isEmpty { onInputLost?() }
        if kind == .buttons {
            suppression = RemotePowerSuppression()
            onInterception?(false)
            onInterceptionDetail?(nil)
            onStatus?("等待 Siri Remote 连接")
        } else { touchReconnect.stop(); onTouchStatus?("等待遥控器触控接口") }
    }

    func stop() {
        for kind in RemoteHIDInterface.allCases { close(kind) }
    }

    private func didMatch(_ device: IOHIDDevice) {
        func property(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? -1 }
        guard let kind = RemoteHIDInterface.identify(vendor: property(kIOHIDVendorIDKey), product: property(kIOHIDProductIDKey), page: property(kIOHIDPrimaryUsagePageKey), usage: property(kIOHIDPrimaryUsageKey)) else { return }
        let id = Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        remoteDevices[id] = kind
        if kind == .buttons {
            suppression.buttonInterfacePresent = true
            onInterception?(suppression.active)
            onStatus?("已发现 Siri Remote，控制已启用")
        } else {
            onTouchStatus?("已识别 Siri Remote 触控身份接口")
            let location = property(kIOHIDLocationIDKey)
            if location >= 0 { touchReconnect.connect(locationID: UInt32(truncatingIfNeeded: location)) }
        }
    }

    private func didRemove(_ device: IOHIDDevice) {
        let id = Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        guard let kind = remoteDevices.removeValue(forKey: id) else { return }
        buttonValues.remove(deviceID: id)
        touches.removeValue(forKey: id); coordinateAxes.removeValue(forKey: id)
        if kind == .buttons {
            suppression.buttonInterfacePresent = remoteDevices.values.contains(.buttons)
            onInterception?(suppression.active)
            if !suppression.buttonInterfacePresent {
                onInputLost?()
                onStatus?("等待 Siri Remote 连接")
            }
        } else if !remoteDevices.values.contains(.touch) {
            touchReconnect.stop()
            onInputLost?()
            onTouchStatus?("等待遥控器触控接口")
        }
    }

    private func didReceive(_ value: IOHIDValue) {
        let device = IOHIDElementGetDevice(IOHIDValueGetElement(value))
        let deviceID = Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        guard let kind = remoteDevices[deviceID] else { return }
        let usage = Int(IOHIDElementGetUsage(IOHIDValueGetElement(value)))
        let page = Int(IOHIDElementGetUsagePage(IOHIDValueGetElement(value)))
        let integer = IOHIDValueGetIntegerValue(value)
        if kind == .buttons {
            guard buttonValues.changed(deviceID: deviceID, page: page, usage: usage, value: integer) else { return }
            onDiagnostic?(String(format: "HID page=0x%02X usage=0x%02X value=%d", page, usage, integer))
        }
        if kind == .touch && ((page == 0x01 && (usage == 0x30 || usage == 0x31)) || (page == 0x0D && (usage == 0x42 || usage == 0x33))) {
            var sample = touches[deviceID] ?? RemoteTouchSample(x: 0.5, y: 0.5, touching: false)
            if page == 0x01 {
                let element = IOHIDValueGetElement(value)
                let minimum = IOHIDElementGetLogicalMin(element)
                let maximum = IOHIDElementGetLogicalMax(element)
                guard maximum > minimum else { return }
                let coordinate = min(1, max(0, Double(integer - minimum) / Double(maximum - minimum)))
                if usage == 0x30 { sample.x = coordinate } else { sample.y = 1 - coordinate }
                coordinateAxes[deviceID, default: []].insert(usage)
            } else { sample.touching = integer != 0 }
            sample.timestamp = ProcessInfo.processInfo.systemUptime
            touches[deviceID] = sample
            if coordinateAxes[deviceID]?.count == 2 {
                onTouchStatus?("已识别 Siri Remote 标准触控接口")
                onTouch?(sample)
            }
            return
        }
        if kind == .buttons { onUsage?(page, usage, integer != 0) }
    }

    static func standardKey(page: Int, usage: Int) -> RemoteKey? {
        // HID usage names alone do not describe this remote's physical keys.
        if page == 0x01 && usage == 0x86 { return .menu }
        guard page == 0x0C else { return nil }
        switch usage {
        case 0x30: return .power
        case 0x60, 0x223: return .tv
        case 0x40, 0x46: return .menu
        case 0x04, 0xCF: return .voice
        case 0x80, 0x41: return .center
        case 0x42: return .touchUp
        case 0x43: return .touchDown
        case 0x44: return .touchLeft
        case 0x45: return .touchRight
        case 0xB0, 0xCD: return .playPause
        case 0xE2: return .mute
        case 0xE9: return .volumeUp
        case 0xEA: return .volumeDown
        default: return nil
        }
    }
}
