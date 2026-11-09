// Web part of the Media Session plugin: the now-playing controls of the browser through the Media Session API, whose actions the media keys of keyboards and headsets send too. The browser shows the controls only while the page plays sound. The page imports this module before the runtime starts and calls its `load` function with the context of the plugin.
export default function load(context) {
    // The actions of the browser for the names of the commands, where the toggle has none, so the play and pause actions send the toggle of an app that offers only the toggle.
    const actions = { play: "play", pause: "pause", stop: "stop", next: "nexttrack", previous: "previoustrack", seek: "seekto" };
    let artworkUrl = null;

    // The browser tells no duration back, so the plugin keeps the one that the app gave last.
    let shownDuration = 0;

    const setActions = (commands) => {
        const session = navigator.mediaSession;
        for (const [command, action] of Object.entries(actions)) {
            const toggles = (command === "play" || command === "pause") && !(command in commands) && "togglePlayPause" in commands;
            const sent = toggles ? "togglePlayPause" : command;
            const handler = sent in commands ? (details) => context.emit("command", sent === "seek" ? { command: sent, position: details.seekTime || 0 } : { command: sent }) : null;
            // A browser that lacks an action throws, and the action is then not offered there.
            try {
                session.setActionHandler(action, handler);
            } catch {
                continue;
            }
        }
    };

    const releaseArtwork = () => {
        if (artworkUrl) {
            URL.revokeObjectURL(artworkUrl);
            artworkUrl = null;
        }
    };

    // A browser without the Media Session API shows no controls, so the calls change nothing there.
    context.register("setNowPlaying", (params) => {
        if (!("mediaSession" in navigator)) {
            return null;
        }

        const session = navigator.mediaSession;
        releaseArtwork();
        setActions(params.commands);
        if (params.artwork && params.artwork.length > 0) {
            artworkUrl = URL.createObjectURL(new Blob([params.artwork]));
        }

        shownDuration = params.duration;
        session.metadata = new MediaMetadata({ title: params.title, artist: params.artist, album: params.album, artwork: artworkUrl ? [{ src: artworkUrl }] : [] });
        session.playbackState = params.playing ? "playing" : "paused";
        if (params.duration > 0 && session.setPositionState) {
            session.setPositionState({ duration: params.duration, position: Math.min(params.position, params.duration), playbackRate: 1 });
        }
        return null;
    });

    context.register("clear", () => {
        if (!("mediaSession" in navigator) || !navigator.mediaSession.metadata) {
            return null;
        }

        const session = navigator.mediaSession;
        releaseArtwork();
        setActions({});
        shownDuration = 0;
        session.metadata = null;
        session.playbackState = "none";
        return null;
    });

    context.register("nowPlaying", () => {
        const metadata = "mediaSession" in navigator ? navigator.mediaSession.metadata : null;
        if (!metadata) {
            return null;
        }
        return { title: metadata.title, artist: metadata.artist, album: metadata.album, duration: shownDuration, playing: navigator.mediaSession.playbackState === "playing", artwork: metadata.artwork.length > 0 };
    });
}
