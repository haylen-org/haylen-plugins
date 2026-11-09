# 🧭 Google Analytics — plugin guide

This folder is the Google Analytics plugin of Haylen: the events, the user ID, the user properties and the consent of a web app, sent to a property of Google Analytics 4 through gtag.js. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It wraps gtag.js alone, through the commands that the documentation of Google Analytics 4 describes, and serves the web alone. Google serves gtag.js only at an address without a version, which the README states, so the plugin follows the current documentation of the commands it uses.
- The Lua API of `source/init.lua` checks its arguments, and the web module fails a call with a typed code and a sentence for every input it does not take. A page that cannot load gtag.js starts anyway and fails every call with the code `unavailable`, so no event stays on the page without a word and no call waits for an answer that never comes.
- Every change updates `README.md`, which documents the complete Lua API, the setup and what each platform answers, and the sample in `sample/`, which shows every call.

## Verify

- Lua: `luac -p source/init.lua sample/source/main.lua`.
- Web: `node --check web/google-analytics.js`.
- The sample: `haylen app build sample --target web` and `haylen app run sample --target web` in Debug and in Release, in a browser, where every button answers and the network panel shows the requests to `https://www.google-analytics.com/g/collect`.
- A test app that calls every function from `source/main.lua`, run in headless Chrome with its console and its requests printed, shows each answer, the event names in `en`, the user ID in `uid`, the user properties in `up.<name>` and the consent in `gcs` of the requests, and with `www.googletagmanager.com` blocked shows that every call fails with the code `unavailable`.
