import Foundation
import AppKit
import Darwin

/// The native callback can run off the main actor. Snapshot the current
/// registration before queuing its frame, then reject it after any rebind.
final class RemoteTouchFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var token: UUID?
    private var device: UInt?
    func activate(device: UInt) {
        lock.lock(); defer { lock.unlock() }
        token = UUID(); self.device = device
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        token = nil; device = nil
    }
    func capture(device: UInt?) -> UUID? {
        lock.lock(); defer { lock.unlock() }
        guard device == nil || device == self.device else { return nil }
        return token
    }
    func accepts(_ captured: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return token == captured
    }
}

// Use MultitouchSupport for pointer coordinates. Its HID digitizer
// descriptor is opaque, not a pair of standard HID X/Y values. Scope this
// adapter to the exact HID LocationID; never select an arbitrary trackpad.
@MainActor
final class RemoteMultitouchMonitor: RemoteMultitouchMonitoring {
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32, UnsafeMutableRawPointer?) -> Int32
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    typealias BuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias DeviceState = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias Register = @convention(c) (UnsafeMutableRawPointer, FrameCallback, UnsafeMutableRawPointer?) -> Void
    typealias Unregister = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void
    var onSample: ((RemoteTouchSample) -> Void)?
    var onStatus: ((String) -> Void)?
    private let library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private var device: UnsafeMutableRawPointer?
    private var list: CFArray?
    private nonisolated let frameGate = RemoteTouchFrameGate()
    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let library, let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
    @discardableResult
    func start(locationID: UInt32) -> Bool {
        stop()
        guard let create = symbol("MTDeviceCreateList", as: CreateList.self),
              let getID = symbol("MTDeviceGetDeviceID", as: GetID.self),
              let builtIn = symbol("MTDeviceIsBuiltIn", as: BuiltIn.self),
              let register = symbol("MTRegisterContactFrameCallbackWithRefcon", as: Register.self),
              symbol("MTUnregisterContactFrameCallback", as: Unregister.self) != nil,
              symbol("MTDeviceStop", as: Stop.self) != nil,
              let start = symbol("MTDeviceStart", as: Start.self), let list = create()?.takeRetainedValue() else {
            onStatus?("遥控器触控驱动接口不可用"); return false
        }
        self.list = list
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let candidate = UnsafeMutableRawPointer(mutating: raw)
            guard !builtIn(candidate) else { continue }
            if let valid = symbol("MTDeviceIsValid", as: DeviceState.self), !valid(candidate) { continue }
            var id: UInt64 = 0
            guard getID(candidate, &id) == 0, UInt32(truncatingIfNeeded: id) == locationID else { continue }
            device = candidate
            frameGate.activate(device: UInt(bitPattern: candidate))
            register(candidate, Self.callback, Unmanaged.passUnretained(self).toOpaque())
            let result = start(candidate, 0)
            guard result == 0 else {
                stop()
                onStatus?("遥控器触控启动状态：\(result)")
                return false
            }
            if let running = symbol("MTDeviceIsRunning", as: DeviceState.self), !running(candidate) {
                stop()
                onStatus?("已识别触控身份；等待匹配多点触控通道")
                return false
            }
            onStatus?("已连接 Siri Remote 多点触控通道")
            return true
        }
        self.list = nil
        onStatus?("已识别触控身份；等待匹配多点触控通道")
        return false
    }
    func stop() {
        frameGate.reset()
        if let device {
            symbol("MTUnregisterContactFrameCallback", as: Unregister.self)?(device, Self.callback)
            symbol("MTDeviceStop", as: Stop.self)?(device)
        }
        device = nil; list = nil
    }
    private static let callback: FrameCallback = { source, contacts, count, timestamp, _, context in
        guard let context else { return 0 }
        let owner = Unmanaged<RemoteMultitouchMonitor>.fromOpaque(context).takeUnretainedValue()
        guard let captured = owner.frameGate.capture(device: source.map { UInt(bitPattern: $0) }) else { return 0 }
        // bottom-origin Y, and averages coordinates when multiple contacts are
        // active. Release/proximity records must not move the pointer.
        var active: [RemoteTouchSample] = []
        if count > 0 && count <= 32, let contacts {
            for index in 0..<Int(count) {
                let contact = contacts.advanced(by: index * 0x60)
                let state = contact.load(fromByteOffset: 0x14, as: Int32.self)
                let x = Double(contact.load(fromByteOffset: 0x20, as: Float.self))
                let y = Double(contact.load(fromByteOffset: 0x24, as: Float.self))
                if let sample = RemoteTouchSample.multitouch(x: x, y: y, state: state, timestamp: timestamp), sample.touching {
                    active.append(sample)
                }
            }
        }
        let sample = active.isEmpty
            ? RemoteTouchSample(x: 0.5, y: 0.5, touching: false, timestamp: timestamp)
            : RemoteTouchSample(x: active.reduce(0) { $0 + $1.x } / Double(active.count),
                                y: active.reduce(0) { $0 + $1.y } / Double(active.count),
                                touching: true, timestamp: timestamp)
        Task { @MainActor in
            guard owner.device != nil, owner.frameGate.accepts(captured) else { return }
            owner.onSample?(sample)
        }
        return 0
    }
}
