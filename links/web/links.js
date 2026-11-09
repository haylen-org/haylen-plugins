// Web part of the Links plugin. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin.
export default function load(context) {
    // Answers `links.open` with `true` once the url opened in a new tab. A browser opens a tab only shortly after an input of the person, such as a click or a key, and tells only that it blocked one, which fails with the code `denied`.
    context.register("open", (params) => {
        const opened = window.open(params.url, "_blank");
        if (!opened) {
            throw Object.assign(new Error("The browser blocked the new tab, because it opens one only shortly after an input of the person, such as a click or a key."), { code: "denied" });
        }
        opened.opener = null;
        return true;
    });
}
