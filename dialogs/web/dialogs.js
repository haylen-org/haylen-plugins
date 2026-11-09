// Web part of the Dialogs plugin. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin. A message is a modal `<dialog>` element in the colors of the page. The pickers are the file picker of the browser, which hands the picked files to the Lua API as bytes, and its save picker where it has one, or a download elsewhere. A message that the app gives up closes, while a picker of the browser stays open, since pages cannot close it, and its answer goes nowhere.

const kActivationMessage = "The browser shows its file pickers only right after a click, a tap or a key press of the user, so the app asks for them from an input handler.";
const kFolderMessage = "Browsers give pages no paths of folders, so the web opens no folders.";
const kSteps = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
const kStyle = [
    ".haylen-dialogs{box-sizing:border-box;width:calc(100% - 32px);max-width:440px;max-height:calc(100% - 32px);overflow:auto;padding:20px 20px 16px;border:none;border-radius:12px;border-top:4px solid #0a84ff;background:#fff;color:#1c1c1e;box-shadow:0 16px 48px rgba(0,0,0,.35);font:15px/1.45 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;}",
    ".haylen-dialogs::backdrop{background:rgba(0,0,0,.45);}",
    ".haylen-dialogs[data-kind=warning]{border-top-color:#ff9f0a;}",
    ".haylen-dialogs[data-kind=error]{border-top-color:#ff453a;}",
    ".haylen-dialogs h2{margin:0 0 8px;font-size:17px;font-weight:600;}",
    ".haylen-dialogs p{margin:0 0 18px;white-space:pre-wrap;overflow-wrap:anywhere;}",
    ".haylen-dialogs-buttons{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:8px;}",
    ".haylen-dialogs button{font:inherit;min-width:72px;padding:7px 14px;border-radius:8px;border:1px solid #c7c7cc;background:#f2f2f7;color:inherit;cursor:pointer;}",
    ".haylen-dialogs button:first-child{border-color:#0a84ff;background:#0a84ff;color:#fff;}",
    ".haylen-dialogs button:focus-visible{outline:2px solid #0a84ff;outline-offset:2px;}",
    "@media (prefers-color-scheme:dark){.haylen-dialogs{background:#2c2c2e;color:#f2f2f7;}.haylen-dialogs button{border-color:#48484a;background:#3a3a3c;}}",
].join("");

const failure = (message, code) => Object.assign(new Error(message), { code });

const hasActivation = () => !navigator.userActivation || navigator.userActivation.isActive;

const requireActivation = () => {
    if (!hasActivation()) {
        throw failure(kActivationMessage, "denied");
    }
};

let styled = false;

const addStyle = () => {
    if (styled) {
        return;
    }
    const style = document.createElement("style");
    style.textContent = kStyle;
    document.head.appendChild(style);
    styled = true;
};

const createButton = (label, answer, close) => {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;
    button.addEventListener("click", () => close(answer));
    return button;
};

// The arrows move the focus to the next or the previous button, and wrap around at the ends.
const moveFocus = (buttons, event) => {
    const step = kSteps[event.key] || 0;
    if (step === 0) {
        return;
    }
    event.preventDefault();
    const current = buttons.indexOf(event.target);
    const next = (current + step + buttons.length) % buttons.length;
    buttons[next].focus();
};

// The message shows in the top layer of the page, over the canvas and over an element in fullscreen, and takes the focus. Its first button is the default one, the arrows move between its buttons, Tab stays inside it and Escape dismisses it.
const showMessage = (params, signal) =>
    new Promise((resolve) => {
        addStyle();
        const dialog = document.createElement("dialog");
        dialog.className = "haylen-dialogs";
        dialog.dataset.kind = params.kind;
        if (params.title) {
            const title = document.createElement("h2");
            title.textContent = params.title;
            dialog.appendChild(title);
        }
        const text = document.createElement("p");
        text.textContent = params.text;
        dialog.appendChild(text);

        const previous = document.activeElement;
        const close = (answer) => {
            dialog.remove();
            if (previous instanceof HTMLElement && previous.isConnected) {
                previous.focus({ preventScroll: true });
            }
            resolve(answer);
        };
        const row = document.createElement("div");
        row.className = "haylen-dialogs-buttons";
        const buttons = params.buttons.map((label, index) => createButton(label, index + 1, close));
        row.append(...buttons);
        dialog.appendChild(row);

        dialog.addEventListener("cancel", (event) => {
            event.preventDefault();
            close(null);
        });
        dialog.addEventListener("keydown", (event) => moveFocus(buttons, event));
        signal.addEventListener("abort", () => close(null), { once: true });

        (document.fullscreenElement || document.body).appendChild(dialog);
        dialog.showModal();
        buttons[0].focus({ preventScroll: true });
    });

// Browsers answer a closed picker with the `cancel` event of the input, which older browsers never send, so their picker answers nothing until the person picks.
const chooseFiles = (accept, multiple) =>
    new Promise((resolve) => {
        const input = document.createElement("input");
        input.type = "file";
        input.multiple = multiple;
        input.accept = accept;
        input.style.cssText = "position:fixed;left:0;top:0;width:1px;height:1px;opacity:0;pointer-events:none;";
        input.addEventListener("cancel", () => {
            input.remove();
            resolve(null);
        });
        input.addEventListener("change", () => {
            input.remove();
            resolve([...input.files]);
        });
        document.body.appendChild(input);
        input.click();
    });

// The picked files cross as bytes, which the Lua API writes into its folder of the storage.
const readFiles = async (files) => {
    if (files === null) {
        return null;
    }
    try {
        const contents = await Promise.all(files.map((file) => file.arrayBuffer()));
        return files.map((file, index) => ({ name: file.name, data: new Uint8Array(contents[index]) }));
    } catch (error) {
        throw failure('The picked files could not be read, and the browser reported "' + error.message + '".', "failed");
    }
};

const getPatterns = (filter) => filter.extensions.map((extension) => "." + extension);

const getAccept = (filters) => {
    const patterns = (filters || []).flatMap(getPatterns);
    return patterns.join(",");
};

// A download needs no activation, and the browser decides where it goes, so the saved file has no path.
const download = (name, bytes) => {
    const blob = new Blob([bytes], { type: "application/octet-stream" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = name;
    link.style.display = "none";
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
    return { name };
};

// The picker lists the types by their extensions, and every type needs a MIME type, which extensions alone do not tell, so all of them name bytes.
const getTypes = (filters) => (filters || []).map((filter) => ({ description: filter.name, accept: { "application/octet-stream": getPatterns(filter) } }));

// The save picker of the File System Access API writes where the person picks, and browsers without it download the data. The file keeps no path, since the page never sees one.
const saveFile = async (params, signal) => {
    if (!window.showSaveFilePicker) {
        return download(params.name, params.data);
    }
    requireActivation();
    let handle;
    try {
        handle = await window.showSaveFilePicker({ suggestedName: params.name, types: getTypes(params.filters) });
    } catch (error) {
        if (error.name === "AbortError") {
            return null;
        }
        throw failure('The save picker failed, and the browser reported "' + error.message + '".', "failed");
    }
    if (signal.aborted) {
        return null;
    }
    try {
        const writable = await handle.createWritable();
        await writable.write(params.data);
        await writable.close();
    } catch (error) {
        throw failure('The file "' + handle.name + '" could not be written, and the browser reported "' + error.message + '".', "failed");
    }
    return { name: handle.name };
};

export default function load(context) {
    context.register("message", (params, call) => showMessage(params, call.signal));

    context.register("openFiles", async (params) => {
        requireActivation();
        return readFiles(await chooseFiles(getAccept(params.filters), params.multiple));
    });

    context.register("saveFile", (params, call) => saveFile(params, call.signal));

    context.register("openFolder", () => {
        throw failure(kFolderMessage, "unsupported");
    });

    // The file picker of images is the photo picker of the browser, which lets phones pick from their photos and cameras, and needs no permission.
    context.register("openPhotos", async (params) => {
        requireActivation();
        return readFiles(await chooseFiles("image/*", params.multiple));
    });
}
