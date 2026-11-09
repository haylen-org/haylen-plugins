// Web part of the local plugin of the sample. It registers a permission of every state through the Permissions plugin, whose permission `asked` is the permission of notifications of the browser, which shows its prompt, and answers `use` once the page holds the permission that the call names.
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

// A permission whose state never changes, which a request answers without a prompt.
const fixed = (name, state) => ({
    name,
    capability: "the permission \"" + name + "\" of the sample",
    check: () => state,
    request: () => state,
});

// The browser names a permission that the person has not decided yet `default`.
const requestNotifications = async () => {
    const answer = await Notification.requestPermission();
    return answer === "default" ? "prompt" : answer;
};

export default function load(context) {
    registerPermission(context, fixed("held", "granted"));
    registerPermission(context, { name: "asked", capability: "notifications", needs: { api: "Notification" }, query: "notifications", request: requestNotifications });
    registerPermission(context, fixed("refused", "denied"));
    registerPermission(context, fixed("untold", "unknown"));
    registerPermission(context, { ...fixed("absent", "unsupported"), unavailable: () => "The sample has the permission \"absent\" on no device." });

    context.register("use", async (params) => {
        await requirePermission(context, params.name);
        return "The plugin used the permission \"" + params.name + "\".";
    });
}
