# 🧭 Playgama Bridge — plugin guide

This folder is the Playgama Bridge plugin of Haylen: the platform and the player, interstitial, rewarded and banner ads, the storage of the platform and the messages of the game, on the game platforms that Playgama Bridge reaches from the web. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both.
- It wraps Playgama Bridge alone, through its documented API, and serves the web alone, since the bridge has no SDK for apps. The README states every other platform as a gap with its reason.
- The default of `bridgeUrl` names one exact release of the npm package `@playgama/bridge`, its latest release, and never a channel of the CDN of Playgama, which changes under the app. A new release of the bridge changes that default, the version of the README and the code of `web/playgama.js` that its API needs, after its notes say what changed.
- The Lua API of `source/init.lua` checks its arguments and options, raising `Unknown option "<key>".` for an option it does not know, and the web module fails a call with a typed code and a sentence for every input it does not take and every refusal of the bridge, so no call waits for an answer that never comes.
- The interstitial and rewarded ads are screens, which the engine covers the app for, and only one ad shows at a time. The storage keeps texts, which the app encodes itself.
- Every change updates `README.md`, which documents the complete Lua API, the setup and what each kind of site answers, and the sample in `sample/`, which shows every call.

## Verify

- Lua: `luac -p source/init.lua sample/source/main.lua`.
- Web: `node --check web/playgama.js`.
- The sample: `haylen app build sample --target web` and `haylen app run sample --target web` in Debug and in Release, in a browser, where the bridge plays the platform `mock` and every button answers as the README says.
- A test app that calls every function from `source/main.lua`, run in headless Chrome with its console printed, shows each answer, and with the address of the bridge blocked shows that the page keeps the app from starting with the error of its loader.
