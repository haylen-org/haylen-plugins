// Web part of the Share plugin, built on the Web Share API. The browser shows its share sheet only right after a press of the person, so a share that the app starts from a button runs within the moment the browser allows, and a share that comes later fails with the code `notAllowed`. The browser tells whether the person shared or closed the sheet, but not where they shared.
const failure = (message, code) => Object.assign(new Error(message), { code });

export default function load(context) {
    context.register("share", async (params) => {
        context.require({ secureContext: true, api: "navigator.share", permissionsPolicy: "web-share" });

        const shareData = {};
        if (params.title !== undefined) {
            shareData.title = params.title;
        }
        if (params.text !== undefined) {
            shareData.text = params.text;
        }
        if (params.url !== undefined) {
            shareData.url = params.url;
        }
        if (params.files !== undefined && params.files.length > 0) {
            shareData.files = params.files.map((file) => new File([file.bytes], file.name, { type: file.type }));
        }
        if (navigator.canShare && !navigator.canShare(shareData)) {
            throw failure("The browser cannot share this content, such as files of this type.", "unsupported");
        }

        // The browser refuses a share without a recent press and a share of content that it blocks with the same error, so the activation of the page tells them apart where the browser reports it.
        const pressed = navigator.userActivation ? navigator.userActivation.isActive : false;
        try {
            await navigator.share(shareData);
            return { shared: true };
        } catch (error) {
            if (error.name === "AbortError") {
                return { shared: false };
            }
            if (error.name === "NotAllowedError" && !pressed) {
                throw failure("The browser shows its share sheet only right after a press of the person, so share from the press of a button.", "notAllowed");
            }
            if (error.name === "NotAllowedError") {
                throw failure("The browser refused to share this content, such as files of this type.", "unsupported");
            }
            throw failure(`The browser did not share: ${error.message}`, "failed");
        }
    });
}
