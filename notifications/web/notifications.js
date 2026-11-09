// Web part of the Notifications plugin, built on the Notification API. A page without a service worker keeps no notification that waits once it closes and cannot list the notifications that the browser shows, so the plugin waits for each notification with a timer of the page, shows it while the page stays open, and answers `delivered` with the code `unsupported`.
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

const failure = (message, code) => Object.assign(new Error(message), { code });

// The longest delay of `setTimeout`, about 24 days, past which the page sets one timer after another.
const kLongestTimeout = 2147483647;

// The Notification API names the state of a permission that it has not asked for yet `default`, and the states `granted` and `denied` as the Permissions plugin does.
const stateOf = (permission) => (permission === "default" ? "prompt" : permission);

export default function load(context) {
    const waiting = new Map();
    const shown = new Map();

    registerPermission(context, {
        name: "notifications",
        capability: "notifications",
        needs: { secureContext: true, api: "Notification" },
        check: () => stateOf(Notification.permission),
        request: async () => stateOf(await Notification.requestPermission()),
    });

    const describe = (entry) => ({ id: entry.id, title: entry.title, body: entry.body, date: entry.date, data: entry.data });

    const forget = (id) => {
        const entry = waiting.get(id);
        if (entry) {
            clearTimeout(entry.timer);
            waiting.delete(id);
        }
        shown.get(id)?.close();
    };

    // The tag of a notification replaces the one of the same id that the browser still shows, and its click brings the page to the front and reaches the app as `opened`. Browsers on phones, such as Chrome on Android, show notifications only through a service worker and throw a `TypeError` here, which the console reports.
    const show = (entry) => {
        waiting.delete(entry.id);
        let notification = null;
        try {
            notification = new Notification(entry.title, { body: entry.body, silent: !entry.sound, tag: "notifications." + entry.id });
        } catch (error) {
            console.warn(`The notification "${entry.id}" did not show, because this browser shows notifications only through a service worker, which the page of the app has not: ${error.message}`);
            return;
        }
        shown.set(entry.id, notification);
        notification.addEventListener("close", () => {
            if (shown.get(entry.id) === notification) {
                shown.delete(entry.id);
            }
        });
        notification.addEventListener("click", () => {
            window.focus();
            notification.close();
            context.emit("opened", { id: entry.id, data: entry.data }, { retain: true });
        });
    };

    const wait = (entry) => {
        const delay = entry.date * 1000 - Date.now();
        if (delay > kLongestTimeout) {
            entry.timer = setTimeout(() => wait(entry), kLongestTimeout);
            return;
        }
        entry.timer = setTimeout(() => show(entry), Math.max(0, delay));
    };

    context.register("schedule", async (params) => {
        await requirePermission(context, "notifications");
        forget(params.id);
        const date = params.date ?? Date.now() / 1000 + params.seconds;
        const entry = { id: params.id, title: params.title, body: params.body, date, sound: params.sound, data: params.data ?? null };
        waiting.set(entry.id, entry);
        wait(entry);
        return { id: entry.id, date };
    });

    context.register("cancel", (params) => {
        forget(params.id);
        return {};
    });

    context.register("cancelAll", () => {
        for (const id of new Set([...waiting.keys(), ...shown.keys()])) {
            forget(id);
        }
        return {};
    });

    context.register("pending", () => {
        const entries = [...waiting.values()];
        entries.sort((first, second) => first.date - second.date);
        return entries.map(describe);
    });

    context.register("delivered", () => {
        throw failure("A page without a service worker cannot list the notifications that the browser shows.", "unsupported");
    });
}
