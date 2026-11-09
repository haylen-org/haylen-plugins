// Web part of the Haptics plugin. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin. Browsers vibrate phones through the Vibration API and offer pages no haptic engine.
export default function load(context) {
    const unsupported = () => {
        throw Object.assign(new Error("Browsers offer pages no haptic engine, only the vibration of \"haptics.vibrate\"."), { code: "unsupported" });
    };

    // Answers `haptics.vibrate` with `true` once the device vibrates. A browser vibrates only after an input of the person, such as a tap, and refuses before, which fails with the code `denied`.
    context.register("vibrate", (params) => {
        context.require({ api: "navigator.vibrate" });

        const milliseconds = Math.max(1, Math.round(params.seconds * 1000));
        if (!navigator.vibrate(milliseconds)) {
            throw Object.assign(new Error("The browser vibrates only after an input of the person, such as a tap."), { code: "denied" });
        }
        return true;
    });
    context.register("impact", unsupported);
    context.register("selection", unsupported);
    context.register("notification", unsupported);
}
