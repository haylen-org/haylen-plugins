// Web part of the Bluetooth plugin, built on Web Bluetooth. A page never scans by itself: the browser shows its chooser of nearby devices, the person picks one, and the page reaches only that device and only the services that the scan named. So `scan` opens the chooser, sends the device that the person picked as one `found` event, and gives its answer once the chooser closes, and the browser shows the chooser only right after a press of the person.
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

const failure = (message, code) => Object.assign(new Error(message), { code });

// The properties of a characteristic that the app sees, which the properties of Web Bluetooth name the same way.
const kProperties = ["read", "write", "writeWithoutResponse", "notify", "indicate"];

const kNeeds = { secureContext: true, api: "navigator.bluetooth", permissionsPolicy: "bluetooth" };

// The page reaches a device through the chooser of each scan, which is how the person allows it, so the page holds the permission wherever the browser has a Bluetooth adapter.
async function availability() {
    if (await navigator.bluetooth.getAvailability()) {
        return "granted";
    }
    return { state: "unsupported", message: "This device has no Bluetooth adapter that the browser reaches." };
}

// An empty list of Lua crosses the bridge as an empty object.
function texts(params, key) {
    const value = params[key];
    if (Array.isArray(value)) {
        return value;
    }
    if (value !== null && typeof value === "object" && Object.keys(value).length === 0) {
        return [];
    }
    throw failure(`The call needs "${key}" as a list of strings.`, "invalidParams");
}

function properties(characteristic) {
    return kProperties.filter((property) => characteristic.properties[property]);
}

// Web Bluetooth fails with a `DOMException`, whose number is no code of the bridge, so such an error fails the call with `code` and the message of the browser, and a failure of the plugin keeps its own code.
function described(error, code) {
    if (typeof error.code === "string") {
        return error;
    }
    return failure(`The browser answered with an error: ${error.message}`, code);
}

export default function load(context) {
    const devices = new Map();
    const listeners = new Map();

    registerPermission(context, { name: "bluetooth", capability: "Bluetooth", needs: kNeeds, check: availability, request: availability });

    // Answers `bluetooth.<method>` once the app holds the permission, and fails an error of the browser with the code `failed`, or `connectFailed` for a connection.
    const handle = (method, body, code = "failed") => {
        context.register(method, async (params) => {
            await requirePermission(context, "bluetooth");
            try {
                return await body(params);
            } catch (error) {
                throw described(error, code);
            }
        });
    };

    const device = (id) => {
        const found = devices.get(id);
        if (!found) {
            throw failure(`No device has the id "${id}". Scan for it first.`, "unknownDevice");
        }
        return found;
    };

    const connected = (id) => {
        const found = device(id);
        if (!found.gatt.connected) {
            throw failure(`The device "${id}" is not connected. Connect to it first.`, "notConnected");
        }
        return found;
    };

    const service = async (params) => {
        const server = connected(params.id).gatt;
        try {
            return await server.getPrimaryService(params.service);
        } catch {
            throw failure(`The device has no service "${params.service}" among the services that the scan named.`, "unknownService");
        }
    };

    const characteristic = async (params) => {
        const found = await service(params);
        try {
            return await found.getCharacteristic(params.characteristic);
        } catch {
            throw failure(`The service "${params.service}" has no characteristic "${params.characteristic}".`, "unknownCharacteristic");
        }
    };

    const key = (params) => `${params.id}/${params.service}/${params.characteristic}`;

    const bytes = (view) => new Uint8Array(view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength));

    // The services that the scan names are the only ones that the page may reach on the device, so a scan without services finds every device and reaches none of its services.
    handle("scan", async (params) => {
        const services = texts(params, "services");
        const filters = services.map((uuid) => ({ services: [uuid] }));
        const options = services.length > 0 ? { filters, optionalServices: services } : { acceptAllDevices: true };
        let picked = null;
        try {
            picked = await navigator.bluetooth.requestDevice(options);
        } catch (error) {
            if (error.name === "NotFoundError") {
                return {};
            }
            if (error.name === "SecurityError") {
                throw failure("The browser shows its chooser of devices only right after a press of the person, so scan from the press of a button.", "notAllowed");
            }
            throw failure(`The browser did not scan: ${error.message}`, "scanFailed");
        }

        if (!devices.has(picked.id)) {
            devices.set(picked.id, picked);
            picked.addEventListener("gattserverdisconnected", () => context.emit("disconnected", { id: picked.id, reason: "The connection ended." }));
        }
        context.emit("found", { id: picked.id, name: picked.name ?? null, services: [] }, { batched: true });
        return {};
    });

    // The chooser of the browser is the scan, which ends once the person picks a device or closes it.
    context.register("stopScan", () => ({}));

    const connect = async (params) => {
        const found = device(params.id);
        await found.gatt.connect();
        return { id: found.id, name: found.name ?? null };
    };
    handle("connect", connect, "connectFailed");

    context.register("disconnect", (params) => {
        const found = devices.get(params.id);
        if (found && found.gatt.connected) {
            found.gatt.disconnect();
        }
        return {};
    });

    handle("services", async (params) => {
        const services = await connected(params.id).gatt.getPrimaryServices();
        return services.map((service) => service.uuid);
    });

    handle("characteristics", async (params) => {
        const found = await service(params);
        const characteristics = await found.getCharacteristics();
        return characteristics.map((each) => ({ uuid: each.uuid, properties: properties(each) }));
    });

    handle("read", async (params) => {
        const found = await characteristic(params);
        return { value: bytes(await found.readValue()) };
    });

    handle("write", async (params) => {
        const found = await characteristic(params);
        if (params.response) {
            await found.writeValueWithResponse(params.value);
        } else {
            await found.writeValueWithoutResponse(params.value);
        }
        return {};
    });

    handle("subscribe", async (params) => {
        const found = await characteristic(params);
        if (!found.properties.notify && !found.properties.indicate) {
            throw failure(`The characteristic "${params.characteristic}" neither notifies nor indicates.`, "notSupported");
        }

        if (!listeners.has(key(params))) {
            const listener = () => {
                const change = { id: params.id, service: params.service, characteristic: params.characteristic, value: bytes(found.value) };
                context.emit("changed", change, { batched: true });
            };
            found.addEventListener("characteristicvaluechanged", listener);
            listeners.set(key(params), { found, listener });
        }
        await found.startNotifications();
        return {};
    });

    handle("unsubscribe", async (params) => {
        const subscription = listeners.get(key(params));
        if (subscription) {
            listeners.delete(key(params));
            subscription.found.removeEventListener("characteristicvaluechanged", subscription.listener);
            await subscription.found.stopNotifications();
        }
        return {};
    });
}
