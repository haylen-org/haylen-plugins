// Web part of the Permissions plugin: the registration of the permissions that the web modules of plugins own, the handlers `<id>.permission` and `<id>.requestPermission` that answer them with the name of the state, or fail with the code `unsupported`, the reason and `data.missing`, and `requirePermission`, which asks for a permission before a plugin uses the capability. The modules of the plugins that depend on it import it with `import { registerPermission, requirePermission } from "haylen-plugin:permissions";`.
const kStates = ["granted", "prompt", "denied", "unknown", "unsupported"];

const kKeys = ["name", "capability", "needs", "unavailable", "query", "unnamed", "check", "request"];

// The permissions that the web module of each plugin registered, by the id of the plugin.
const registered = new Map();

const failure = (message, code, data) => Object.assign(new Error(message), { code, data });

// An answer of the code of a plugin is the name of a state, or `{state, message}` for `unsupported` with the reason.
const readAnswer = (value) => {
    const answer = typeof value === "string" ? { state: value } : value;
    if (!answer || !kStates.includes(answer.state)) {
        throw new TypeError("A permission of a plugin answers \"granted\", \"prompt\", \"denied\", \"unknown\" or \"unsupported\", or {state, message}.");
    }

    return { state: answer.state, message: answer.message || "" };
};

// Answers the state of a name of the Permissions API, or nothing for a name that the browser does not know.
const queryPermission = async (name) => {
    if (!navigator.permissions || typeof navigator.permissions.query !== "function") {
        return null;
    }

    try {
        return (await navigator.permissions.query({ name })).state;
    } catch {
        return null;
    }
};

// A capability that the browser lacks, or that the page lacks a requirement of, answers `unsupported` before anything asks.
const blockedPermission = (context, permission) => {
    try {
        context.require(permission.needs);
    } catch (error) {
        if (error.code !== "unsupported") {
            throw error;
        }
        return { state: "unsupported", message: error.message, missing: error.data.missing };
    }

    const unavailable = permission.unavailable ? permission.unavailable() : null;
    return unavailable ? { state: "unsupported", message: unavailable } : null;
};

const checkPermission = async (context, permission) => {
    const blocked = blockedPermission(context, permission);
    if (blocked) {
        return blocked;
    }

    if (permission.check) {
        return readAnswer(await permission.check());
    }

    return { state: (await queryPermission(permission.query)) || permission.unnamed };
};

// A permission shows the prompt of the browser only while its state is `prompt`, or `unknown` where the browser tells nothing before it asks, and answers any other state without asking.
const requestPermission = async (context, permission) => {
    const current = await checkPermission(context, permission);
    if (current.state !== "prompt" && current.state !== "unknown") {
        return current;
    }

    return readAnswer(await permission.request());
};

// The sentence of a use of a capability that a request did not allow, the same on every platform: after `prompt`, where the browser did not show its prompt, it says that the app may ask again later, and after `denied` it names how to ask for it again.
const refusal = (context, permission, answered) => {
    const call = context.id + ".requestPermission('" + permission.name + "')";
    if (answered === "prompt") {
        return "The system did not show its prompt for " + permission.capability + ", so the app does not hold it yet. Ask for it again later with \"" + call + "\".";
    }

    return "The person has not allowed " + permission.capability + ". Ask for it with \"" + call + "\", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.";
};

// Checks every key of a permission and fills in the state of a name that the Permissions API does not know, which is `unknown` unless the permission names another.
const createPermission = (id, spec) => {
    for (const key of Object.keys(spec || {})) {
        if (!kKeys.includes(key)) {
            throw new TypeError("A permission of the plugin \"" + id + "\" takes \"" + kKeys.join("\", \"") + "\", not \"" + key + "\".");
        }
    }

    if (!spec || typeof spec.name !== "string" || spec.name === "" || typeof spec.capability !== "string" || typeof spec.request !== "function") {
        throw new TypeError("A permission of the plugin \"" + id + "\" needs a \"name\", a \"capability\" in words and a \"request\" function.");
    }

    for (const key of ["check", "unavailable"]) {
        if (spec[key] !== undefined && typeof spec[key] !== "function") {
            throw new TypeError("The \"" + key + "\" of the permission \"" + spec.name + "\" of the plugin \"" + id + "\" is a function.");
        }
    }

    if (spec.check === undefined && typeof spec.query !== "string") {
        throw new TypeError("The permission \"" + spec.name + "\" of the plugin \"" + id + "\" tells its state through a \"query\" of the Permissions API or a \"check\" function.");
    }

    if (spec.unnamed !== undefined && !kStates.includes(spec.unnamed)) {
        throw new TypeError("The \"unnamed\" state of the permission \"" + spec.name + "\" of the plugin \"" + id + "\" is \"granted\", \"prompt\", \"denied\", \"unknown\" or \"unsupported\".");
    }

    return { ...spec, needs: spec.needs || {}, unnamed: spec.unnamed || "unknown" };
};

// A state of `unsupported` fails the call the way `requirePermission` does.
const unsupported = (answer) => failure(answer.message, "unsupported", answer.missing ? { missing: answer.missing } : undefined);

// The handlers answer the state of the permissions that the plugin registered, and a name that it did not register on the web fails with the code `unsupported`.
const answerPermission = async (context, params, asking) => {
    const name = params && params.name;
    const permission = registered.get(context.id).get(name);
    if (!permission) {
        throw failure("The plugin \"" + context.id + "\" registers no permission \"" + name + "\" on this platform.", "unsupported");
    }

    const answer = asking ? await requestPermission(context, permission) : await checkPermission(context, permission);
    if (answer.state === "unsupported") {
        throw unsupported(answer);
    }

    return answer.state;
};

// Registers a permission that the plugin of the context declares in the `permissions` of its `plugin.json`, so the handlers `<id>.permission` and `<id>.requestPermission` answer for it. The permission is `{name, capability, needs, unavailable, query, unnamed, check, request}`: its name, the capability in words, what the page needs for it as `context.require` takes it, a function that answers the sentence of a device without the capability or nothing, the name of the Permissions API that tells its state, the state for a browser that does not know that name, a function that tells the state instead, and the function that shows the prompt. The functions `check` and `request` answer the name of a state or `{state, message}`. Throws for a permission that does not have that shape and for a name that the plugin registered before.
export function registerPermission(context, spec) {
    const permission = createPermission(context.id, spec);
    if (!registered.has(context.id)) {
        registered.set(context.id, new Map());
        context.register("permission", (params) => answerPermission(context, params, false));
        context.register("requestPermission", (params) => answerPermission(context, params, true));
    }

    const permissions = registered.get(context.id);
    if (permissions.has(permission.name)) {
        throw new Error("The plugin \"" + context.id + "\" registered the permission \"" + permission.name + "\" twice.");
    }

    permissions.set(permission.name, permission);
}

// Asks for the permission where the page does not hold it, and fails with the code `denied` when the person refused it or the browser did not show its prompt, or `unsupported` with what the page lacks or for a name that the plugin did not register, as plugins expect before they use a capability. A state that the browser tells nothing of lets the use try.
export async function requirePermission(context, name) {
    const permission = registered.has(context.id) ? registered.get(context.id).get(name) : undefined;
    if (!permission) {
        throw failure("The plugin \"" + context.id + "\" requires the permission \"" + name + "\", which it did not register with \"registerPermission\".", "unsupported");
    }

    const answer = await requestPermission(context, permission);
    if (answer.state === "denied" || answer.state === "prompt") {
        throw failure(refusal(context, permission, answer.state), "denied");
    }

    if (answer.state === "unsupported") {
        throw unsupported(answer);
    }
}

export default function load() {}
