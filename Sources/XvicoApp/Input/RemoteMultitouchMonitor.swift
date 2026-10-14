import Foundation
import AppKit
import Darwin

// Use MultitouchSupport for pointer coordinates. Its HID digitizer
// descriptor is opaque, not a pair of standard HID X/Y values. Scope this
// adapter to the exact HID LocationID; never select an arbitrary trackpad.
@MainActor
final class RemoteMultitouchMonitor {
    typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32, UnsafeMutableRawPointer?) -> Int32
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    typealias BuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias Register = @convention(c) (UnsafeMutableRawPointer, FrameCallback, UnsafeMutableRawPointer?) -> Void
    typealias Unregister = @convention(c) (UnsafeMutableRawPointer, FrameCallback) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void
    var onSample: ((RemoteTouchSample) -> Void)?
    var onStatus: ((String) -> Void)?
    private let library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private var device: UnsafeMutableRawPointer?
    private var list: CFArray?
    private var activeToken: UUID?
    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let library, let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
    func start(locationID: UInt32) {
        stop()
        guard let create = symbol("MTDeviceCreateList", as: CreateList.self),
              let getID = symbol("MTDeviceGetDeviceID", as: GetID.self),
              let builtIn = symbol("MTDeviceIsBuiltIn", as: BuiltIn.self),
              let register = symbol("MTRegisterContactFrameCallbackWithRefcon", as: Register.self),
              let start = symbol("MTDeviceStart", as: Start.self), let list = create()?.takeRetainedValue() else {
            onStatus?("遥控器触控驱动接口不可用"); return
        }
        self.list = list
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let candidate = UnsafeMutableRawPointer(mutating: raw)
            guard !builtIn(candidate) else { continue }
            var id: UInt64 = 0
            guard getID(candidate, &id) == 0, UInt32(truncatingIfNeeded: id) == locationID else { continue }
            device = candidate; activeToken = UUID()
            register(candidate, Self.callback, Unmanaged.passUnretained(self).toOpaque())
            let result = start(candidate, 0)
            onStatus?(result == 0 ? "已连接 Siri Remote 多点触控通道" : "遥控器触控启动状态：\(result)")
            return
        }
        onStatus?("已识别触控身份；等待匹配多点触控通道")
    }
    func stop() {
        activeToken = nil
        if let device {
            symbol("MTUnregisterContactFrameCallback", as: Unregister.self)?(device, Self.callback)
            symbol("MTDeviceStop", as: Stop.self)?(device)
        }
        device = nil; list = nil
    }
    private static let callback: FrameCallback = { _, contacts, count, timestamp, _, context in
        guard let context else { return 0 }
        let owner = Unmanaged<RemoteMultitouchMonitor>.fromOpaque(context).takeUnretainedValue()
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
            guard owner.device != nil, owner.activeToken != nil else { return }
            owner.onSample?(sample)
        }
        return 0
    }
}
