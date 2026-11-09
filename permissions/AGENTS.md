# 🧭 Permissions — plugin guide

This folder is the Permissions plugin of Haylen, which holds the permission contract of every plugin that owns a permission: the five states, the registration of each permission in the native parts of the plugins, the queue of the prompts of the system and the Lua API that checks and asks for a permission. It has Swift in `apple/`, a Kotlin library module in `android/` and an ES module in `web/`, and no library for the desktops, whose plugins answer their own permissions. Its Lua API lives in `source/init.lua`, and `README.md` documents it with what each platform answers. This file is binding for every change of the plugin.

## Rules

- The plugin follows the `AGENTS.md` of the Haylen repository and the plugin format of its `docs/platform/plugins.md`. Code, comments and docs are written in English, comments are rare complete sentences, and nothing names another engine or a company beyond the platforms.
- It uses the APIs of each platform alone, never a third-party library, and it declares no permission of its own, neither in its `plugin.json` nor in the manifest of its Android module.
- The states are `granted`, `prompt`, `denied`, `unknown` and `unsupported` on every platform, and the bridge protocol is the same everywhere: `<id>.permission` reads the state without asking, `<id>.requestPermission` shows the prompt of the system only while the state is `prompt`, or `unknown` on the web, and both take `{name}` and answer the name of the state, or fail with the code `unsupported`, the reason and `data.missing`. The Lua API returns these platform calls of the owner as they are.
- The two sentences of a refusal are the same on every platform and name `<id>.requestPermission('<name>')`, and the desktop libraries of the plugins use them too.
- The plugin holds what every plugin with a permission needs and nothing of one capability. A plugin that depends on it reaches its Swift in the same app target, its Kotlin through the `api(project(":permissions"))` that the Android backend writes, and its web module through the specifier `haylen-plugin:permissions`.
- On Android one launcher of `RequestMultiplePermissions`, registered under the key `haylen.permissions.request` by `PermissionsPlugin.onActivityCreated`, shows every prompt, and requests wait in one queue, so two prompts never collide.
- Every change updates `README.md`, the Lua API and every native part in the same change, together with the plugins that depend on it, and the sample in `sample/` shows every state.

## Verify

- Run the sample with `haylen app run sample --target macos`, and on the iOS simulator, the Android emulator and the web with `--target`, and check each state, a request of `asked` that the person allows and one that the person refuses.
- Check the Lua with `luac -p source/init.lua`, the web module with `node --check web/permissions.js` and the Swift with `swiftc -typecheck` against the plugin API of the engine, for iOS, Mac Catalyst, macOS, tvOS and visionOS.
- Compile the Kotlin module against the `haylen` library of the engine and run its unit tests, `PermissionQueueTest`, on the JVM with `gradle test`.
