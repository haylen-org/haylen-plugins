// Web part of the App Tracking Transparency plugin. Browsers show no prompt for tracking, so the permission `tracking` answers `granted`. The web has no advertising identifier, so `advertisingId` fails with the code `unsupported`.
import { registerPermission } from "haylen-plugin:permissions";

export default function load(context) {
    registerPermission(context, {
        name: "tracking",
        capability: "tracking across the apps and websites of other companies",
        check: () => "granted",
        request: () => "granted",
    });

    context.register("advertisingId", () => {
        throw Object.assign(new Error("The web has no advertising identifier."), { code: "unsupported" });
    });
}
