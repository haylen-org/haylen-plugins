# 🧭 Play Asset Delivery — plugin guide

This folder is the Play Asset Delivery plugin of Haylen: the named packs of the content of an app as asset packs of Google Play, fast-follow or on-demand, through a source of packs of the content manager of the engine. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both, and the delivery of packs of `docs/content/content.md` and `docs/tools/distribution.md`.
- It uses the library `com.google.android.play:asset-delivery` of Google Play alone, pinned to its latest release in `android/build.gradle.kts`, and adopts its current API with every new release, after its notes say what changed. The README names the versions of the module.
- The source of packs answers with the folder of a pack, or with nothing for a pack that Play does not deliver to the app, so the next source or the content server delivers it, and every other failure fails the load with a typed code and the reason of Play.
- The confirmation of Play is a screen of the plugin, whose launcher every activity registers in `onActivityCreated` under the key `play-asset-delivery.confirm`, outside the keys of the engine, so its result reaches the screen also after Android recreated the activity.
- Every change updates `README.md`, which documents the complete Lua API, the setup and what each kind of install answers.

## Verify

- Lua: `luac -p source/init.lua`.
- Android: an app with two named packs, one in `fastFollowPacks` and one on demand, such as the Pack Lab app next to the plugins, with the plugin as a reference: `haylen app run <app> --target android --config Release --device emulator-5554`, which installs the bundle in the local testing mode of Play, where both loads give their assets and `state` answers `'completed'`, and `haylen app build <app> --target android --config Release`.
