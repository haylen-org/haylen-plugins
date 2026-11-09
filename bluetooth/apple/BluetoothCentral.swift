import CoreBluetooth
import Foundation

// The central of CoreBluetooth behind the plugin, which lives on the main actor. Its manager starts with the first request of the permission or the first use, since the system shows the prompt of Bluetooth once a manager starts. A manager without a queue of its own delivers its events and those of its devices on the main queue, where the handlers of the plugin run too, so the central conforms to the delegate protocols on the main actor. Each operation that CoreBluetooth answers through a delegate method waits under a key that names what it waits for and the device, and the end of a connection fails everything that waited on that device.
@MainActor
final class BluetoothCentral: NSObject, @MainActor CBCentralManagerDelegate, @MainActor CBPeripheralDelegate {
    struct Target {
        let device: String
        let service: String
        let characteristic: String

        var detail: String {
            service + "/" + characteristic
        }
    }

    // The base of the UUIDs that the Bluetooth SIG assigns, after the 4 or 8 hexadecimal digits of a short UUID.
    private static let base = "-0000-1000-8000-00805f9b34fb"

    private let context: HaylenPluginContext
    private var manager: CBCentralManager?
    private var settling: [CheckedContinuation<Void, Never>] = []
    private var asking: [Permission.Answer] = []
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: Set<UUID> = []
    private var waiting: [String: [CheckedContinuation<Void, Error>]] = [:]
    private var found: Set<UUID> = []
    private var scanEnd: CheckedContinuation<Void, Never>?
    private var scanTimer: Task<Void, Never>?

    init(context: HaylenPluginContext) {
        self.context = context
    }

    // The permission `bluetooth`, whose answer arrives as a change of the state of the manager once the person decided.
    func permission() -> Permission {
        Permission(name: "bluetooth", capability: "Bluetooth", requirements: [.usageDescription("NSBluetoothAlwaysUsageDescription")], state: { answer in
            answer(Self.state(of: CBManager.authorization), nil)
        }, request: { [unowned self] answer in
            self.asking.append(answer)
            self.start()
        })
    }

    private static func state(of authorization: CBManagerAuthorization) -> Permission.State {
        switch authorization {
        case .notDetermined:
            return .prompt
        case .allowedAlways:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    private func start() {
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    // Waits until the manager knows the state of the radio, and fails unless the radio is on.
    private func ready() async throws -> CBCentralManager {
        start()
        guard let manager else {
            throw HaylenFailure("Bluetooth did not start.", code: "failed")
        }
        if manager.state == .unknown || manager.state == .resetting {
            await withCheckedContinuation { settling.append($0) }
        }

        switch manager.state {
        case .poweredOn:
            return manager
        case .poweredOff:
            throw HaylenFailure("Bluetooth is off. The person turns it on in the settings of the system.", code: "poweredOff")
        case .unauthorized:
            throw HaylenFailure("The person has not allowed Bluetooth. Ask for it with \"bluetooth.requestPermission('bluetooth')\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.", code: "denied")
        case .unsupported:
            throw HaylenFailure("This device has no Bluetooth Low Energy.", code: "unsupported")
        default:
            throw HaylenFailure("Bluetooth is not ready.", code: "notReady")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let authorization = CBManager.authorization
        if authorization != .notDetermined {
            let answers = asking
            asking.removeAll()
            for answer in answers {
                answer(Self.state(of: authorization), nil)
            }
        }

        if central.state != .unknown && central.state != .resetting {
            let continuations = settling
            settling.removeAll()
            for continuation in continuations {
                continuation.resume()
            }
        }

        // A radio that turns off ends every connection without a disconnect of each device.
        if central.state != .poweredOn {
            stopScan()
            for peripheral in peripherals.values where connected.contains(peripheral.identifier) {
                ended(peripheral, reason: "Bluetooth turned off.")
            }
        }
    }

    // A scan that runs ends first, so its call gives its answer, and each device reaches the app once per scan.
    func scan(services: [String], seconds: Double) async throws {
        let manager = try await ready()
        stopScan()
        found.removeAll()
        let filter = services.isEmpty ? nil : services.map(Self.uuid)
        manager.scanForPeripherals(withServices: filter, options: nil)

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                scanEnd = continuation
                scanTimer = endScan(after: seconds)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.stopScan()
            }
        }
    }

    // Stops the scan once its seconds passed, unless the task was cancelled because the scan ended first.
    private func endScan(after seconds: Double) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self?.stopScan()
            }
        }
    }

    func stopScan() {
        manager?.stopScan()
        scanTimer?.cancel()
        scanTimer = nil
        let end = scanEnd
        scanEnd = nil
        end?.resume()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripherals[peripheral.identifier] = peripheral
        if !found.insert(peripheral.identifier).inserted {
            return
        }

        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        var device: [String: Any] = ["id": peripheral.identifier.uuidString, "rssi": RSSI.intValue]
        device["name"] = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        device["services"] = services.map(Self.text)
        device["manufacturerData"] = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        context.emit("found", payload: device, retain: false, batched: true)
    }

    // A connection that the app gives up, with a cancel or a timeout, stops its attempt.
    func connect(_ id: String) async throws -> [String: Any] {
        let manager = try await ready()
        let peripheral = try peripheral(id)
        if peripheral.state != .connected {
            peripheral.delegate = self
            let key = key("connect", peripheral)
            let identifier = peripheral.identifier
            try await withTaskCancellationHandler {
                try await wait(key) { manager.connect(peripheral, options: nil) }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.abandon(key, device: identifier)
                }
            }
        }
        var result: [String: Any] = ["id": id]
        result["name"] = peripheral.name
        return result
    }

    // Stops the attempt of a connection that the app gave up.
    private func abandon(_ key: String, device identifier: UUID) {
        if let peripheral = peripherals[identifier] {
            manager?.cancelPeripheralConnection(peripheral)
        }
        finish(key, CancellationError())
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected.insert(peripheral.identifier)
        finish(key("connect", peripheral), nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(key("connect", peripheral), HaylenFailure("The device did not connect: \(error?.localizedDescription ?? "it gave no reason.")", code: "connectFailed"))
    }

    func disconnect(_ id: String) async throws {
        guard let manager else {
            return
        }
        let peripheral = try peripheral(id)
        if peripheral.state == .disconnected {
            return
        }
        try await wait(key("disconnect", peripheral)) { manager.cancelPeripheralConnection(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish(key("disconnect", peripheral), nil)
        ended(peripheral, reason: error?.localizedDescription ?? "The app disconnected.")
    }

    // Fails what waits on the device and tells the app that the connection ended.
    private func ended(_ peripheral: CBPeripheral, reason: String) {
        let marker = ":" + peripheral.identifier.uuidString + ":"
        for key in waiting.keys.filter({ $0.contains(marker) }) {
            finish(key, HaylenFailure("The device disconnected: \(reason)", code: "notConnected"))
        }
        if connected.remove(peripheral.identifier) != nil {
            context.emit("disconnected", payload: ["id": peripheral.identifier.uuidString, "reason": reason], retain: false, batched: false)
        }
    }

    func services(_ id: String) async throws -> [String] {
        let peripheral = try await connectedPeripheral(id)
        try await wait(key("services", peripheral)) { peripheral.discoverServices(nil) }
        return (peripheral.services ?? []).map { Self.text($0.uuid) }
    }

    func characteristics(_ id: String, service uuid: String) async throws -> [[String: Any]] {
        let peripheral = try await connectedPeripheral(id)
        let service = try await self.service(uuid, of: peripheral)
        try await wait(key("characteristics", peripheral, uuid)) { peripheral.discoverCharacteristics(nil, for: service) }
        return (service.characteristics ?? []).map { ["uuid": Self.text($0.uuid), "properties": Self.properties($0.properties)] }
    }

    func read(_ target: Target) async throws -> Data {
        let (peripheral, characteristic) = try await self.characteristic(target)
        try await wait(key("read", peripheral, target.detail)) { peripheral.readValue(for: characteristic) }
        return characteristic.value ?? Data()
    }

    // A write without a response waits while the queue of CoreBluetooth is full, and every write with a response waits for its own answer, in order.
    func write(_ value: Data, to target: Target, response: Bool) async throws {
        let (peripheral, characteristic) = try await self.characteristic(target)
        if !response {
            while !peripheral.canSendWriteWithoutResponse {
                try await wait(key("writable", peripheral)) {}
            }
            peripheral.writeValue(value, for: characteristic, type: .withoutResponse)
            return
        }
        try await queue(key("write", peripheral, target.detail)) { peripheral.writeValue(value, for: characteristic, type: .withResponse) }
    }

    func setNotify(_ enabled: Bool, for target: Target) async throws {
        let (peripheral, characteristic) = try await self.characteristic(target)
        guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            throw HaylenFailure("The characteristic \"\(target.characteristic)\" neither notifies nor indicates.", code: "notSupported")
        }
        if characteristic.isNotifying == enabled {
            return
        }
        try await wait(key("notify", peripheral, target.detail + "/" + String(enabled))) { peripheral.setNotifyValue(enabled, for: characteristic) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        finish(key("services", peripheral), error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        finish(key("characteristics", peripheral, Self.text(service.uuid)), error)
    }

    // CoreBluetooth answers reads and notifications with the same method, so a value that a read waits for answers the read, and any other value of a characteristic that notifies reaches the app.
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let service = characteristic.service else {
            return
        }
        let serviceText = Self.text(service.uuid)
        let characteristicText = Self.text(characteristic.uuid)
        let readKey = key("read", peripheral, serviceText + "/" + characteristicText)
        if waiting[readKey] != nil {
            finish(readKey, error)
            return
        }
        if error != nil || !characteristic.isNotifying {
            return
        }
        let change: [String: Any] = ["id": peripheral.identifier.uuidString, "service": serviceText, "characteristic": characteristicText, "value": characteristic.value ?? Data()]
        context.emit("changed", payload: change, retain: false, batched: true)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let service = characteristic.service else {
            return
        }
        finishFirst(key("write", peripheral, Self.text(service.uuid) + "/" + Self.text(characteristic.uuid)), error)
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        finish(key("writable", peripheral), nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let service = characteristic.service else {
            return
        }
        let detail = Self.text(service.uuid) + "/" + Self.text(characteristic.uuid)
        if error != nil {
            finish(key("notify", peripheral, detail + "/true"), error)
            finish(key("notify", peripheral, detail + "/false"), error)
            return
        }
        finish(key("notify", peripheral, detail + "/" + String(characteristic.isNotifying)), nil)
    }

    private func peripheral(_ id: String) throws -> CBPeripheral {
        guard let identifier = UUID(uuidString: id) else {
            throw HaylenFailure("No device has the id \"\(id)\". Scan for it first.", code: "unknownDevice")
        }
        if let known = peripherals[identifier] {
            return known
        }
        if let retrieved = manager?.retrievePeripherals(withIdentifiers: [identifier]).first {
            peripherals[identifier] = retrieved
            return retrieved
        }
        throw HaylenFailure("No device has the id \"\(id)\". Scan for it first.", code: "unknownDevice")
    }

    private func connectedPeripheral(_ id: String) async throws -> CBPeripheral {
        _ = try await ready()
        let peripheral = try peripheral(id)
        guard peripheral.state == .connected else {
            throw HaylenFailure("The device \"\(id)\" is not connected. Connect to it first.", code: "notConnected")
        }
        return peripheral
    }

    // Finds a service of the device, and discovers the services first when it does not know it yet.
    private func service(_ uuid: String, of peripheral: CBPeripheral) async throws -> CBService {
        if let service = peripheral.services?.first(where: { Self.text($0.uuid) == uuid }) {
            return service
        }
        try await wait(key("services", peripheral)) { peripheral.discoverServices(nil) }
        guard let service = peripheral.services?.first(where: { Self.text($0.uuid) == uuid }) else {
            throw HaylenFailure("The device has no service \"\(uuid)\".", code: "unknownService")
        }
        return service
    }

    private func characteristic(_ target: Target) async throws -> (CBPeripheral, CBCharacteristic) {
        let peripheral = try await connectedPeripheral(target.device)
        let service = try await self.service(target.service, of: peripheral)
        if let characteristic = service.characteristics?.first(where: { Self.text($0.uuid) == target.characteristic }) {
            return (peripheral, characteristic)
        }
        try await wait(key("characteristics", peripheral, target.service)) { peripheral.discoverCharacteristics(nil, for: service) }
        guard let characteristic = service.characteristics?.first(where: { Self.text($0.uuid) == target.characteristic }) else {
            throw HaylenFailure("The service \"\(target.service)\" has no characteristic \"\(target.characteristic)\".", code: "unknownCharacteristic")
        }
        return (peripheral, characteristic)
    }

    private func key(_ kind: String, _ peripheral: CBPeripheral, _ detail: String = "") -> String {
        kind + ":" + peripheral.identifier.uuidString + ":" + detail
    }

    // Waits for the answer under `key`. The first to wait starts the operation, and one answer serves every wait, such as two reads of one characteristic.
    private func wait(_ key: String, start: () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let first = waiting[key] == nil
            waiting[key, default: []].append(continuation)
            if first {
                start()
            }
        }
    }

    // Waits for the answer under `key` after starting the operation every time, and each answer serves the oldest wait, such as one write after another.
    private func queue(_ key: String, start: () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiting[key, default: []].append(continuation)
            start()
        }
    }

    private func finish(_ key: String, _ error: Error?) {
        guard let continuations = waiting.removeValue(forKey: key) else {
            return
        }
        for continuation in continuations {
            resume(continuation, error)
        }
    }

    private func finishFirst(_ key: String, _ error: Error?) {
        guard var continuations = waiting[key], !continuations.isEmpty else {
            return
        }
        let continuation = continuations.removeFirst()
        waiting[key] = continuations.isEmpty ? nil : continuations
        resume(continuation, error)
    }

    private func resume(_ continuation: CheckedContinuation<Void, Error>, _ error: Error?) {
        guard let error else {
            continuation.resume()
            return
        }
        if error is HaylenFailure || error is CancellationError {
            continuation.resume(throwing: error)
            return
        }
        continuation.resume(throwing: HaylenFailure("The device answered with an error: \(error.localizedDescription)", code: "failed"))
    }

    static func text(_ uuid: CBUUID) -> String {
        let value = uuid.uuidString.lowercased()
        switch value.count {
        case 4:
            return "0000" + value + base
        case 8:
            return value + base
        default:
            return value
        }
    }

    // CoreBluetooth names the UUIDs of the Bluetooth SIG by their short form.
    private static func uuid(_ text: String) -> CBUUID {
        guard text.hasSuffix(base) else {
            return CBUUID(string: text)
        }
        let short = String(text.prefix(8))
        return CBUUID(string: short.hasPrefix("0000") ? String(short.suffix(4)) : short)
    }

    private static func properties(_ properties: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if properties.contains(.read) {
            names.append("read")
        }
        if properties.contains(.write) {
            names.append("write")
        }
        if properties.contains(.writeWithoutResponse) {
            names.append("writeWithoutResponse")
        }
        if properties.contains(.notify) {
            names.append("notify")
        }
        if properties.contains(.indicate) {
            names.append("indicate")
        }
        return names
    }
}
