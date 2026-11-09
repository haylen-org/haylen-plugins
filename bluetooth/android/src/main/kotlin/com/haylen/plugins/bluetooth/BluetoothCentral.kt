package com.haylen.plugins.bluetooth

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattConnectionSettings
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.util.isNotEmpty
import dev.haylen.HaylenBridge
import dev.haylen.HaylenPluginContext
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

// The central of Bluetooth Low Energy behind the plugin. Android runs one operation of GATT at a time on each connection, so each device keeps a queue of operations and starts the next one once the callback of the current one came. The callbacks of Android arrive on threads of the system, and they continue on the main thread, where the handlers run too, so the state of the central belongs to the main thread alone. The plugin asks for the permission `bluetooth` before every call that needs it, so the calls of the system that it guards never miss it.
@SuppressLint("MissingPermission")
class BluetoothCentral(private val context: HaylenPluginContext) {
    class Target(val device: String, val service: UUID, val characteristic: UUID)

    // An operation of GATT, which `start` begins and the callback of its kind ends.
    private class Operation(val kind: String, val target: UUID?, val reply: HaylenBridge.Reply, val start: (BluetoothGatt) -> Boolean, val done: (Int, ByteArray?) -> Unit)

    private inner class Device(val device: BluetoothDevice) {
        var gatt: BluetoothGatt? = null
        var connected = false
        var discovered = false
        val connecting = ArrayList<HaylenBridge.Reply>()
        val disconnecting = ArrayList<HaylenBridge.Reply>()
        val operations = ArrayDeque<Operation>()
        var current: Operation? = null
    }

    private val main = Handler(Looper.getMainLooper())
    private val devices = HashMap<String, Device>()
    private val found = HashSet<String>()
    private var scanReply: HaylenBridge.Reply? = null
    private var scanCallback: ScanCallback? = null
    private val scanEnd = Runnable { stopScan() }

    private fun systemAdapter(): BluetoothAdapter? {
        val manager = context.application().getSystemService(BluetoothManager::class.java)
        return manager?.adapter
    }

    private fun adapter(): BluetoothAdapter {
        val adapter = systemAdapter() ?: throw HaylenBridge.Failure("This device has no Bluetooth.", "unsupported", null)
        if (!adapter.isEnabled) {
            throw HaylenBridge.Failure("Bluetooth is off. The person turns it on in the settings of the system.", "poweredOff", null)
        }
        return adapter
    }

    // A scan that runs ends first, so its call gives its answer, and each device reaches the app once per scan. Android finds nothing before Android 12 while the location of the device is off.
    fun scan(services: List<UUID>, seconds: Double, reply: HaylenBridge.Reply) {
        val scanner = adapter().bluetoothLeScanner ?: throw HaylenBridge.Failure("This device has no Bluetooth Low Energy.", "unsupported", null)
        stopScan()
        found.clear()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                main.post { found(result) }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                main.post { results.forEach { found(it) } }
            }

            override fun onScanFailed(errorCode: Int) {
                main.post { failScan("The scan failed with the code $errorCode of Android.") }
            }
        }
        val filters = services.map { ScanFilter.Builder().setServiceUuid(ParcelUuid(it)).build() }
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(filters, settings, callback)
        scanCallback = callback
        scanReply = reply
        reply.onCancel { stopScan() }
        main.postDelayed(scanEnd, (seconds * 1000).toLong())
    }

    fun stopScan() {
        main.removeCallbacks(scanEnd)
        val callback = scanCallback
        scanCallback = null
        if (callback != null) {
            systemAdapter()?.bluetoothLeScanner?.stopScan(callback)
        }

        val reply = scanReply
        scanReply = null
        reply?.success(JSONObject())
    }

    private fun failScan(message: String) {
        val reply = scanReply
        scanReply = null
        stopScan()
        reply?.failure(message, "scanFailed", null)
    }

    // The manufacturer data starts with the company id in little endian, as the advertisement holds it and as Apple platforms give it.
    private fun found(result: ScanResult) {
        val address = result.device.address
        devices.getOrPut(address) { Device(result.device) }
        if (!found.add(address)) {
            return
        }

        val record = result.scanRecord
        val device = JSONObject().put("id", address).put("rssi", result.rssi)
        (record?.deviceName ?: result.device.name)?.let { device.put("name", it) }
        val services = JSONArray()
        record?.serviceUuids?.forEach { services.put(it.uuid.toString()) }
        device.put("services", services)
        val manufacturers = record?.manufacturerSpecificData
        if (manufacturers != null && manufacturers.isNotEmpty()) {
            val company = manufacturers.keyAt(0)
            val companyBytes = byteArrayOf((company and 0xff).toByte(), (company shr 8 and 0xff).toByte())
            device.put("manufacturerData", companyBytes + manufacturers.valueAt(0))
        }
        context.emit("found", device, false, true)
    }

    private fun device(id: String): Device {
        devices[id]?.let { return it }
        if (!BluetoothAdapter.checkBluetoothAddress(id)) {
            throw HaylenBridge.Failure("No device has the id \"$id\". Scan for it first.", "unknownDevice", null)
        }
        val device = Device(adapter().getRemoteDevice(id))
        devices[id] = device
        return device
    }

    private fun connectedDevice(id: String): Device {
        adapter()
        val device = device(id)
        if (!device.connected) {
            throw HaylenBridge.Failure("The device \"$id\" is not connected. Connect to it first.", "notConnected", null)
        }
        return device
    }

    // A connection that the app gives up, with a cancel or a timeout, stops its attempt.
    fun connect(id: String, reply: HaylenBridge.Reply) {
        adapter()
        val device = device(id)
        if (device.connected) {
            reply.success(described(device))
            return
        }
        device.connecting.add(reply)
        reply.onCancel {
            device.connecting.remove(reply)
            if (device.connecting.isEmpty() && !device.connected) {
                closed(device)
            }
        }
        if (device.gatt != null) {
            return
        }
        device.gatt = connectGatt(device)
        if (device.gatt == null) {
            val replies = ArrayList(device.connecting)
            device.connecting.clear()
            replies.forEach { it.failure("Android did not start the connection to the device.", "connectFailed", null) }
        }
    }

    // Android 17 takes the settings of a connection and the executor of its callbacks, which earlier versions take one by one.
    private fun connectGatt(device: Device): BluetoothGatt? {
        val application = context.application()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.CINNAMON_BUN) {
            val settings = BluetoothGattConnectionSettings.Builder().setTransport(BluetoothDevice.TRANSPORT_LE).build()
            return device.device.connectGatt(settings, application.mainExecutor, callback(device))
        }
        @Suppress("DEPRECATION")
        return device.device.connectGatt(application, false, callback(device), BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect(id: String, reply: HaylenBridge.Reply) {
        val device = devices[id]
        val gatt = device?.gatt
        if (device == null || gatt == null) {
            reply.success(JSONObject())
            return
        }
        device.disconnecting.add(reply)
        gatt.disconnect()
    }

    private fun described(device: Device): JSONObject {
        val result = JSONObject().put("id", device.device.address)
        device.device.name?.let { result.put("name", it) }
        return result
    }

    private fun callback(device: Device) = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            main.post { connectionChanged(device, gatt, status, newState) }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            main.post { operationEnded(device, "services", null, status, null) }
        }

        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            main.post { operationEnded(device, "read", characteristic.uuid, status, value) }
        }

        @Deprecated("Android 12 and earlier call this method with the value in the characteristic.")
        override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            @Suppress("DEPRECATION")
            val value = characteristic.value
            main.post { operationEnded(device, "read", characteristic.uuid, status, value) }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            main.post { operationEnded(device, "write", characteristic.uuid, status, null) }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            main.post { operationEnded(device, "notify", descriptor.characteristic.uuid, status, null) }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            main.post { changed(device, characteristic, value) }
        }

        @Deprecated("Android 12 and earlier call this method with the value in the characteristic.")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            val value = characteristic.value.clone()
            main.post { changed(device, characteristic, value) }
        }
    }

    private fun connectionChanged(device: Device, gatt: BluetoothGatt, status: Int, newState: Int) {
        if (newState == BluetoothProfile.STATE_CONNECTED) {
            device.connected = true
            val replies = ArrayList(device.connecting)
            device.connecting.clear()
            replies.forEach { it.success(described(device)) }
            return
        }
        if (newState != BluetoothProfile.STATE_DISCONNECTED) {
            return
        }

        val wasConnected = device.connected
        val failures = ArrayList(device.connecting)
        device.connecting.clear()
        failures.forEach { it.failure("The device did not connect: ${reason(status)}", "connectFailed", null) }
        val replies = ArrayList(device.disconnecting)
        device.disconnecting.clear()
        replies.forEach { it.success(JSONObject()) }
        closed(device)
        if (wasConnected) {
            val why = if (replies.isEmpty()) reason(status) else "The app disconnected."
            val payload = JSONObject()
            payload.put("id", device.device.address)
            payload.put("reason", why)
            context.emit("disconnected", payload)
        }
    }

    // Ends the connection of the device and fails every operation that waited on it.
    private fun closed(device: Device) {
        device.gatt?.close()
        device.gatt = null
        device.connected = false
        device.discovered = false
        val pending = listOfNotNull(device.current) + device.operations
        device.current = null
        device.operations.clear()
        pending.forEach { it.reply.failure("The device disconnected.", "notConnected", null) }
    }

    private fun reason(status: Int): String {
        return when (status) {
            BluetoothGatt.GATT_SUCCESS -> "The connection ended."
            kConnectionTimeout -> "The connection timed out."
            kTerminatedByPeer -> "The device ended the connection."
            kTerminatedByThisDevice -> "This device ended the connection."
            else -> "The connection failed with the status $status of Android."
        }
    }

    private fun changed(device: Device, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        val change = JSONObject()
        change.put("id", device.device.address)
        change.put("service", characteristic.service.uuid.toString())
        change.put("characteristic", characteristic.uuid.toString())
        change.put("value", value)
        context.emit("changed", change, false, true)
    }

    private fun enqueue(device: Device, operation: Operation) {
        device.operations.addLast(operation)
        next(device)
    }

    private fun next(device: Device) {
        val gatt = device.gatt ?: return
        while (device.current == null) {
            val operation = device.operations.removeFirstOrNull() ?: return
            if (operation.start(gatt)) {
                device.current = operation
            } else {
                operation.reply.failure("Android refused the ${operation.kind} operation, which it runs one at a time on a connection.", "failed", null)
            }
        }
    }

    private fun operationEnded(device: Device, kind: String, target: UUID?, status: Int, value: ByteArray?) {
        val operation = device.current ?: return
        if (operation.kind != kind || (operation.target != null && operation.target != target)) {
            return
        }
        device.current = null
        operation.done(status, value)
        next(device)
    }

    // Android finds the services and their characteristics at once, so every call finds them once per connection first.
    private fun withServices(device: Device, reply: HaylenBridge.Reply, body: (BluetoothGatt) -> Unit) {
        val gatt = device.gatt ?: throw HaylenBridge.Failure("The device is not connected.", "notConnected", null)
        if (device.discovered) {
            body(gatt)
            return
        }
        enqueue(device, Operation("services", null, reply, { it.discoverServices() }) { status, _ ->
            if (status != BluetoothGatt.GATT_SUCCESS) {
                reply.failure("The services of the device were not found: status $status of Android.", "failed", null)
                return@Operation
            }
            device.discovered = true
            try {
                body(gatt)
            } catch (failure: HaylenBridge.Failure) {
                reply.failure(failure)
            }
        })
    }

    private fun characteristic(gatt: BluetoothGatt, target: Target): BluetoothGattCharacteristic {
        val service = gatt.getService(target.service) ?: throw HaylenBridge.Failure("The device has no service \"${target.service}\".", "unknownService", null)
        return service.getCharacteristic(target.characteristic) ?: throw HaylenBridge.Failure("The service \"${target.service}\" has no characteristic \"${target.characteristic}\".", "unknownCharacteristic", null)
    }

    fun services(id: String, reply: HaylenBridge.Reply) {
        val device = connectedDevice(id)
        withServices(device, reply) { gatt ->
            val uuids = JSONArray()
            gatt.services.forEach { uuids.put(it.uuid.toString()) }
            reply.success(uuids)
        }
    }

    fun characteristics(id: String, service: UUID, reply: HaylenBridge.Reply) {
        val device = connectedDevice(id)
        withServices(device, reply) { gatt ->
            val found = gatt.getService(service) ?: throw HaylenBridge.Failure("The device has no service \"$service\".", "unknownService", null)
            val list = JSONArray()
            for (characteristic in found.characteristics) {
                val description = JSONObject()
                description.put("uuid", characteristic.uuid.toString())
                description.put("properties", JSONArray(properties(characteristic.properties)))
                list.put(description)
            }
            reply.success(list)
        }
    }

    fun read(target: Target, reply: HaylenBridge.Reply) {
        val device = connectedDevice(target.device)
        withServices(device, reply) { gatt ->
            val characteristic = characteristic(gatt, target)
            enqueue(device, Operation("read", characteristic.uuid, reply, { it.readCharacteristic(characteristic) }) { status, value ->
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    reply.success(JSONObject().put("value", value ?: ByteArray(0)))
                } else {
                    reply.failure("The device refused the read with the status $status.", "failed", null)
                }
            })
        }
    }

    fun write(target: Target, value: ByteArray, response: Boolean, reply: HaylenBridge.Reply) {
        val device = connectedDevice(target.device)
        withServices(device, reply) { gatt ->
            val characteristic = characteristic(gatt, target)
            val type = if (response) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            enqueue(device, Operation("write", characteristic.uuid, reply, { writeCharacteristic(it, characteristic, value, type) }) { status, _ ->
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    reply.success(JSONObject())
                } else {
                    reply.failure("The device refused the write with the status $status.", "failed", null)
                }
            })
        }
    }

    // Notifications need the switch of Android and the descriptor of the device that turns them on, which takes notifications or indications by the properties of the characteristic.
    fun setNotify(target: Target, enabled: Boolean, reply: HaylenBridge.Reply) {
        val device = connectedDevice(target.device)
        withServices(device, reply) { gatt ->
            val characteristic = characteristic(gatt, target)
            val properties = characteristic.properties
            if (properties and (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE) == 0) {
                throw HaylenBridge.Failure("The characteristic \"${target.characteristic}\" neither notifies nor indicates.", "notSupported", null)
            }
            gatt.setCharacteristicNotification(characteristic, enabled)
            val descriptor = characteristic.getDescriptor(kClientConfiguration)
            if (descriptor == null) {
                reply.success(JSONObject())
                return@withServices
            }
            val value = when {
                !enabled -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                else -> BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            }
            enqueue(device, Operation("notify", characteristic.uuid, reply, { writeDescriptor(it, descriptor, value) }) { status, _ ->
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    reply.success(JSONObject())
                } else {
                    reply.failure("The device refused the notifications with the status $status.", "failed", null)
                }
            })
        }
    }

    private fun writeCharacteristic(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, type: Int): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return gatt.writeCharacteristic(characteristic, value, type) == BluetoothStatusCodes.SUCCESS
        }
        characteristic.writeType = type
        @Suppress("DEPRECATION")
        characteristic.value = value
        @Suppress("DEPRECATION")
        return gatt.writeCharacteristic(characteristic)
    }

    private fun writeDescriptor(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, value: ByteArray): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
        }
        @Suppress("DEPRECATION")
        descriptor.value = value
        @Suppress("DEPRECATION")
        return gatt.writeDescriptor(descriptor)
    }

    private fun properties(properties: Int): List<String> {
        val names = ArrayList<String>()
        if (properties and BluetoothGattCharacteristic.PROPERTY_READ != 0) {
            names.add("read")
        }
        if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) {
            names.add("write")
        }
        if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) {
            names.add("writeWithoutResponse")
        }
        if (properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
            names.add("notify")
        }
        if (properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) {
            names.add("indicate")
        }
        return names
    }

    companion object {
        // The descriptor that turns the notifications and indications of a characteristic on and off.
        private val kClientConfiguration = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        // The statuses of a connection that ends, which the controller of Bluetooth reports and `BluetoothGatt` does not name.
        private const val kConnectionTimeout = 8
        private const val kTerminatedByPeer = 19
        private const val kTerminatedByThisDevice = 22
    }
}
