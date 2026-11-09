# 🧭 Background Assets — plugin guide

This folder is the Background Assets plugin of Haylen: the named packs of the content of an app as asset packs that the App Store hosts, which the system downloads with the install or when the app loads one of their assets, through a source of packs of the content manager of the engine. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`, with the writing, comment and naming standards of both, and the delivery of packs of `docs/content/content.md` and `docs/tools/distribution.md`.
- It uses Background Assets of the system alone, with the current API of the SDK of Xcode and the older calls only behind the checks of availability of the systems that lack the current ones. The README states every platform without the plugin with its reason.
- The source of packs answers with the folder of a pack, or with nothing for a pack that the App Store does not give the app, so the next source or the content server delivers it, and a download that fails fails the load with the reason of the system.
- The release build of Haylen packs the archives and the plugin declares what Background Assets needs in `plugin.json`, the downloader extension, the App Group and the keys of the `Info.plist`, so an app adds nothing by hand.
- Every change updates `README.md`, which documents the complete Lua API, the setup, the check with the mock server and what each platform answers.

## Verify

- Lua: `luac -p source/init.lua`.
- An app with two named packs, one in `prefetchPacks` and one on demand, such as the Pack Lab app next to the plugins, with the plugin as a reference: `haylen app run <app> --target ios-simulator --config Release`, `--target tvos-simulator` and `--target visionos-simulator`, with the mock server of `README.md`, where both loads give their assets and `state` answers `'available'`, and `haylen app build <app> --target ios-simulator --config Release`, `tvos-simulator` and `visionos-simulator`.
- A C++ app made with `haylen new --kind cpp` with the same packs and the plugin as a reference, built with `haylen app run <app> --target ios-simulator --config Release`, whose calls of `background-assets.fetch` and `background-assets.state` through the bridge answer with the folders and the states.
