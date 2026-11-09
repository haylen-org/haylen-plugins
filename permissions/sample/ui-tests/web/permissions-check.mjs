// Opens the site of the sample in a headless Chrome over its debugging protocol and drives it the way a person does through a screen reader: it presses the buttons of the mirror of the UI that the page keeps for screen readers, reads the lines of the log there, and sets the permission of notifications of the browser, which is the permission "asked", to each of its states. It prints what happened as JSON and exits with 1 when a step did not hold.
// Run it with Node: node permissions-check.mjs <debugging port> <page address>
const [port, url] = process.argv.slice(2);
const version = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
const socket = new WebSocket(version.webSocketDebuggerUrl);
const pending = new Map();
const result = { steps: [], failure: null, log: [] };
let id = 0;

const send = (method, params = {}, sessionId = undefined) =>
    new Promise((resolve) => {
        id += 1;
        pending.set(id, resolve);
        socket.send(JSON.stringify(sessionId ? { id, method, params, sessionId } : { id, method, params }));
    });

socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
        pending.get(message.id)(message.result ?? {});
        pending.delete(message.id);
    } else if (message.method === "Runtime.consoleAPICalled") {
        const text = message.params.args.map((arg) => arg.value ?? arg.description).join(" ");
        result.log.push(text);
        if (message.params.type === "error") {
            result.failure = text;
        }
    } else if (message.method === "Runtime.exceptionThrown") {
        result.failure = message.params.exceptionDetails.exception?.description ?? message.params.exceptionDetails.text;
    }
};

await new Promise((resolve) => (socket.onopen = resolve));
const page = (await send("Target.getTargets")).targetInfos.find((target) => target.type === "page");
const { sessionId } = await send("Target.attachToTarget", { targetId: page.targetId, flatten: true });
await send("Runtime.enable", {}, sessionId);
await send("Page.enable", {}, sessionId);
const origin = new URL(url).origin;
const setNotifications = (setting) => send("Browser.setPermission", { permission: { name: "notifications" }, setting, origin });
await setNotifications("prompt");
await send("Page.navigate", { url }, sessionId);

const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true }, sessionId)).result?.value;

// The mirror names a button by its label and holds the text of a label as the text of its element.
const press = (label) => evaluate(`(() => {
    const button = [...document.querySelectorAll("#haylen-accessibility [role=button]")].find((node) => node.getAttribute("aria-label") === ${JSON.stringify(label)});
    if (!button) {
        return false;
    }
    button.click();
    return true;
})()`);
const count = (pattern) => evaluate(`[...document.querySelectorAll("#haylen-accessibility div:not([role])")].filter((node) => node.firstChild && node.firstChild.nodeType === Node.TEXT_NODE && new RegExp(${JSON.stringify(pattern)}, "s").test(node.firstChild.data)).length`);

const wait = async (condition, seconds) => {
    const deadline = Date.now() + seconds * 1000;
    while (Date.now() < deadline) {
        if (await condition()) {
            return true;
        }
        await new Promise((resolve) => setTimeout(resolve, 250));
    }
    return false;
};

const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// Presses the button and waits until the log holds a line that matches the pattern more often than before the press.
const step = async (label, pattern, { literal = true, seconds = 15 } = {}) => {
    const expected = literal ? `^${escape(pattern)}$` : pattern;
    const before = await count(expected);
    const pressed = await wait(() => press(label), seconds);
    const reached = pressed && (await wait(async () => (await count(expected)) > before, seconds));
    result.steps.push({ name: `${label}: ${pattern}`, reached });
    return reached;
};

const ready = await wait(async () => (await count("^Press a button to run its call\\.$")) > 0, 60);
result.steps.push({ name: "ready", reached: ready });
if (ready) {
    for (const [name, state] of [["held", "granted"], ["refused", "denied"], ["untold", "unknown"]]) {
        await step(`Check ${name}`, `The call "states.permission('${name}')" answered "${state}".`);
        await step(`Ask for ${name}`, `The call "states.requestPermission('${name}')" answered "${state}".`);
    }
    await step("Use held", `The call "states.use('held')" answered: The plugin used the permission "held".`);
    await step("Use untold", `The call "states.use('untold')" answered: The plugin used the permission "untold".`);
    await step("Use refused", `^The call "states\\.use\\('refused'\\)" failed with "denied": The person has not allowed the permission "refused" of the sample\\..*`, { literal: false });

    const absent = `failed with "unsupported": The sample has the permission "absent" on no device.`;
    await step("Check absent", `The call "states.permission('absent')" ${absent}`);
    await step("Ask for absent", `The call "states.requestPermission('absent')" ${absent}`);
    await step("Use absent", `The call "states.use('absent')" ${absent}`);
    await step("Check permissions.state('nobody')", `^The call "permissions\\.state\\('nobody'\\)" raised: .*The permission "nobody" belongs to no plugin that the app loaded\\..*`, { literal: false });

    // The browser keeps the permission of notifications per site, which the person changes in the settings of the site and the check sets through the debugging protocol.
    await step("Check permissions.state('asked')", `The call "permissions.state('asked')" answered "prompt".`);
    await setNotifications("denied");
    await step("Check asked", `The call "states.permission('asked')" answered "denied".`);
    await step("Ask for asked", `The call "states.requestPermission('asked')" answered "denied".`);
    await step("Use asked", `^The call "states\\.use\\('asked'\\)" failed with "denied": The person has not allowed notifications\\..*`, { literal: false });
    await setNotifications("granted");
    await step("Check asked", `The call "states.permission('asked')" answered "granted".`);
    await step("Ask for asked", `The call "states.requestPermission('asked')" answered "granted".`);
    await step("Use asked", `The call "states.use('asked')" answered: The plugin used the permission "asked".`);
}

const failed = result.failure !== null || result.steps.some((entry) => !entry.reached);
console.log(JSON.stringify(result, null, 2));
process.exit(failed ? 1 : 0);
