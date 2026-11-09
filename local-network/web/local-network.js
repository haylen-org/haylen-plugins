// Web part of the Local Network plugin: the permission `localNetwork`, which a browser with Local Network Access names `local-network` in the Permissions API. A page has no API that finds or advertises the services of the local network, so `pickService` and `advertise` fail with the code `unsupported`. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin, after the module of the Permissions plugin, which registers and asks for the permissions.
import { registerPermission } from "haylen-plugin:permissions";

const failure = (message, code) => Object.assign(new Error(message), { code });

const kNoServices = "A web page finds and advertises no service of the local network, since browsers give pages no API of DNS-SD.";

// A browser shows its local network prompt when the page first reaches an address of the local network, and offers no call that shows it, so a request answers the state that the browser holds.
const currentState = async () => {
    try {
        return (await navigator.permissions.query({ name: "local-network" })).state;
    } catch {
        return "unknown";
    }
};

export default function load(context) {
    registerPermission(context, { name: "localNetwork", capability: "the local network", query: "local-network", request: currentState });

    context.register("reset", () => null);

    context.register("pickService", () => {
        throw failure(kNoServices, "unsupported");
    });

    context.register("advertise", () => {
        throw failure(kNoServices, "unsupported");
    });

    context.register("stopAdvertising", () => null);
}
