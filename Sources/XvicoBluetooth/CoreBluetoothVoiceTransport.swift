#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

@available(macOS 13.0, *)
public final class CoreBluetoothVoiceTransport: NSObject, VoiceGATTTransport, @unchecked Sendable {
    // All CoreBluetooth state and continuations are confined to this queue.
    private let queue = DispatchQueue(label: "voice-module.bluetooth", qos: .userInitiated)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var selectedRemoteID: UUID?
    private var scan: CheckedContinuation<UUID, Error>?
    private var connection: CheckedContinuation<Void, Error>?
    private var discovery: CheckedContinuation<GATTCharacteristicRef, Error>?
    private var notification: CheckedContinuation<Void, Error>?
    private var writeAcknowledgement: CheckedContinuation<Void, Error>?
    private var timeout: DispatchWorkItem?
    private var broadScan: DispatchWorkItem?
    private var operation = UUID()
    public var onNotification: ((Data) -> Void)?
    public var onDiagnostic: ((String) -> Void)?
    public var onDisconnect: ((String) -> Void)?

    public init(preferredRemoteID: UUID? = nil) {
        selectedRemoteID = preferredRemoteID
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    public func scanForVoiceRemote() async throws -> UUID {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UUID, Error>) in
            queue.async {
                guard self.scan == nil else { continuation.resume(throwing: VoiceMonitorError.transport("重复连接请求")); return }
                self.scan = continuation
                self.setTimeout("未能找到可连接的 Siri Remote")
                if self.central.state == .poweredOn { self.findRemote() }
                else if self.central.state != .unknown && self.central.state != .resetting {
                    self.fail(VoiceMonitorError.bluetoothUnavailable)
                }
            }
        }
    }

    private func findRemote() {
        guard scan != nil else { return }
        // An already-paired device need not advertise during normal operation.
        if let id = selectedRemoteID, let target = central.retrievePeripherals(withIdentifiers: [id]).first {
            found(target, detail: "找到上次使用的遥控器"); return
        }
        for service in [CBUUID(nsuuid: VoiceGATTConstants.serviceUUID), CBUUID(string: "1812")] {
            if let target = central.retrieveConnectedPeripherals(withServices: [service]).first(where: isRemote) {
                found(target, detail: "找到已连接的 Siri Remote"); return
            }
        }
        onDiagnostic?("扫描遥控器语音服务")
        central.scanForPeripherals(withServices: [CBUUID(nsuuid: VoiceGATTConstants.serviceUUID)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.scan != nil else { return }
            self.onDiagnostic?("查找 Siri Remote 广播")
            self.central.stopScan()
            self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        broadScan = item; queue.asyncAfter(deadline: .now() + 4, execute: item)
    }
    private func isRemote(_ device: CBPeripheral) -> Bool {
        device.name?.localizedCaseInsensitiveContains("Siri Remote") == true || device.identifier == selectedRemoteID
    }
    private func found(_ device: CBPeripheral, detail: String) {
        guard let continuation = scan else { return }
        clearTimeout(); broadScan?.cancel(); broadScan = nil; central.stopScan()
        peripheral = device; scan = nil
        onDiagnostic?(detail)
        continuation.resume(returning: device.identifier)
    }

    public func connect(to remoteID: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let target = self.peripheral, target.identifier == remoteID else {
                    continuation.resume(throwing: VoiceMonitorError.remoteNotFound); return
                }
                if target.state == .connected { continuation.resume(); return }
                self.connection = continuation; self.setTimeout("连接遥控器超时")
                self.onDiagnostic?("连接 Siri Remote 语音接口")
                self.central.connect(target)
            }
        }
    }
    public func discoverVoiceCharacteristic() async throws -> GATTCharacteristicRef {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GATTCharacteristicRef, Error>) in
            queue.async {
                guard let target = self.peripheral, target.state == .connected else {
                    continuation.resume(throwing: VoiceMonitorError.remoteNotFound); return
                }
                self.discovery = continuation; self.setTimeout("读取遥控器语音服务超时")
                target.delegate = self
                self.onDiagnostic?("读取语音服务；按键连接不代表语音服务可见")
                target.discoverServices([CBUUID(nsuuid: VoiceGATTConstants.serviceUUID)])
            }
        }
    }
    public func setNotify(_ enabled: Bool, on reference: GATTCharacteristicRef) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let target = self.peripheral, let characteristic = self.characteristic,
                      characteristic.uuid == CBUUID(nsuuid: reference.uuid), reference.supportsNotify else {
                    continuation.resume(throwing: VoiceMonitorError.characteristicNotFound); return
                }
                if characteristic.isNotifying == enabled { continuation.resume(); return }
                self.notification = continuation; self.setTimeout("订阅语音通知超时")
                target.setNotifyValue(enabled, for: characteristic)
            }
        }
    }
    public func write(_ data: Data, to reference: GATTCharacteristicRef, withResponse: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let target = self.peripheral, let characteristic = self.characteristic,
                      characteristic.uuid == CBUUID(nsuuid: reference.uuid) else {
                    continuation.resume(throwing: VoiceMonitorError.characteristicNotFound); return
                }
                guard characteristic.properties.contains(withResponse ? .write : .writeWithoutResponse) else {
                    continuation.resume(throwing: VoiceMonitorError.enableCommandFailed("语音特征不支持此写入方式")); return
                }
                if withResponse {
                    self.writeAcknowledgement = continuation; self.setTimeout("语音启用命令确认超时")
                }
                target.writeValue(data, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)
                if !withResponse {
                    self.onDiagnostic?("已发送 AF 启用命令；等待实际音频")
                    continuation.resume()
                }
            }
        }
    }
    public func disconnect() {
        queue.async {
            self.fail(CancellationError())
            if let target = self.peripheral {
                target.delegate = nil
                self.central.cancelPeripheralConnection(target)
            }
            self.peripheral = nil; self.characteristic = nil
        }
    }
    private func setTimeout(_ detail: String) {
        clearTimeout(); let token = operation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.operation == token else { return }
            self.fail(VoiceMonitorError.transport(detail))
        }
        timeout = item; queue.asyncAfter(deadline: .now() + 12, execute: item)
    }
    private func clearTimeout() { operation = UUID(); timeout?.cancel(); timeout = nil }
    private func fail(_ error: Error) {
        clearTimeout(); broadScan?.cancel(); broadScan = nil; central.stopScan()
        let scan = scan; self.scan = nil
        let connection = connection; self.connection = nil
        let discovery = discovery; self.discovery = nil
        let notification = notification; self.notification = nil
        let write = writeAcknowledgement; writeAcknowledgement = nil
        scan?.resume(throwing: error); connection?.resume(throwing: error)
        discovery?.resume(throwing: error); notification?.resume(throwing: error); write?.resume(throwing: error)
    }
}

@available(macOS 13.0, *)
extension CoreBluetoothVoiceTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { findRemote() }
        else if central.state != .unknown && central.state != .resetting {
            fail(VoiceMonitorError.bluetoothUnavailable)
            onDisconnect?("蓝牙未就绪或未授权")
        }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if isRemote(peripheral) { found(peripheral, detail: "找到 Siri Remote 广播") }
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == self.peripheral else { return }
        clearTimeout(); let result = connection; connection = nil; result?.resume()
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        fail(VoiceMonitorError.transport(error?.localizedDescription ?? "连接失败"))
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == self.peripheral else { return }
        fail(VoiceMonitorError.transport(error?.localizedDescription ?? "语音通道已断开"))
        characteristic = nil; onDisconnect?(error?.localizedDescription ?? "语音通道已断开")
    }
}

@available(macOS 13.0, *)
extension CoreBluetoothVoiceTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == self.peripheral, discovery != nil else { return }
        if let error { fail(VoiceMonitorError.transport(error.localizedDescription)); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(nsuuid: VoiceGATTConstants.serviceUUID) }) else {
            fail(VoiceMonitorError.serviceNotFound); return
        }
        peripheral.discoverCharacteristics([CBUUID(nsuuid: VoiceGATTConstants.notificationUUID)], for: service)
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == self.peripheral, discovery != nil else { return }
        if let error { fail(VoiceMonitorError.transport(error.localizedDescription)); return }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(nsuuid: VoiceGATTConstants.notificationUUID) }) else {
            fail(VoiceMonitorError.characteristicNotFound); return
        }
        self.characteristic = characteristic; clearTimeout()
        let result = discovery; discovery = nil
        result?.resume(returning: GATTCharacteristicRef(uuid: VoiceGATTConstants.notificationUUID,
            supportsNotify: characteristic.properties.contains(.notify),
            supportsWriteWithoutResponse: characteristic.properties.contains(.writeWithoutResponse)))
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral, characteristic == self.characteristic, notification != nil else { return }
        if let error { fail(VoiceMonitorError.notificationSubscriptionFailed(error.localizedDescription)); return }
        guard characteristic.isNotifying else { fail(VoiceMonitorError.notificationSubscriptionFailed("语音通知未启用")); return }
        clearTimeout(); let result = notification; notification = nil; result?.resume()
        onDiagnostic?("已订阅语音通知")
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral, characteristic == self.characteristic, writeAcknowledgement != nil else { return }
        if let error { fail(VoiceMonitorError.enableCommandFailed(error.localizedDescription)); return }
        clearTimeout(); let result = writeAcknowledgement; writeAcknowledgement = nil; result?.resume()
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral, characteristic == self.characteristic,
              error == nil, let data = characteristic.value else { return }
        onNotification?(data)
    }
}
#endif
