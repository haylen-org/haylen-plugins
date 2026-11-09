# 🔐 Permissions

The Permissions plugin for [Haylen](https://github.com/haylen-org/haylen) apps holds the permission contract of every plugin that owns a permission, such as the camera, the microphone or the location. It gives every platform the same five states, `granted`, `prompt`, `denied`, `unknown` and `unsupported`, registers the permissions of the native part of each plugin, shows the prompts of the system one at a time, and offers the Lua API that checks and asks for a permission. The app reaches it through the functions of each plugin, such as `camera.permission()` and `camera.requestPermission()`, or by the name of the permission with `permissions.state(name)` and `permissions.request(name)`.

| Platform | Native part | What it does |
| --- | --- | --- |
| iPhone, iPad, Mac Catalyst, macOS app, tvOS and visionOS | `apple/`, Swift | `Permission` and `Permissions`, which the Swift of the plugins that depend on it uses in the same app target. |
| Android | The library module in `android/` | `Permission`, `Permissions` and the queue of prompts in the package `com.haylen.plugins.permissions`, with one launcher of `RequestMultiplePermissions` for every activity. |
| Web | `web/permissions.js` | `registerPermission` and `requirePermission`, which the web modules of the plugins import from `haylen-plugin:permissions`. |
| Windows, Linux and the desktop player | None | The library of `native/` of each plugin answers its own permission handlers, so the plugin has nothing native to share there. |

## Installation

A plugin that owns a permission lists `permissions` in the `dependencies` of its `plugin.json`, so the app lists both plugins:

```sh
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path permissions --reference --app my-app
haylen plugin add https://github.com/haylen-org/haylen-plugins --ref main --path camera --reference --app my-app
```

The commands list the plugins in the `plugins` section of the `haylen.json` of the app as references to their folders in the repository of the Haylen plugins:

```json
{
    "plugins": {
        "permissions": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "permissions"
        },
        "camera": {
            "git": "https://github.com/haylen-org/haylen-plugins",
            "ref": "main",
            "path": "camera"
        }
    }
}
```

Without `--reference`, the commands copy the plugins into `plugins/permissions/` and `plugins/camera/` of the app instead. The plugin has no parameters. To stay on one version of the plugins, the app names a commit in `ref` instead of the branch `main`.

## Lua API

```lua
local permissions = require('permissions')
```

The plugin knows the plugin that owns each permission, which the Lua module of that plugin declares when the app requires it. A check or a request is the platform call `<id>.permission` or `<id>.requestPermission` of the owner, with the parameters `{name}`, so every function returns a call of `haylen.platform`, whose `await` inside a coroutine gives the state, or `nil` and a `PlatformError` with `message`, `code` and `data`. Like every platform call, a failure that nothing awaits stops the app.

| State | Meaning |
| --- | --- |
| `'granted'` | The app holds the permission, or the platform needs none for it. |
| `'prompt'` | The person was not asked yet, so a request shows the prompt of the system. |
| `'denied'` | The person refused it, or the system no longer asks. A request then answers `'denied'` at once, and the person allows it in the settings of the system. |
| `'unknown'` | The platform tells nothing until the app tries, such as a browser that asks at the first use, and the use of the capability asks the person. |

A platform without the capability, such as a device without a camera, fails the call with the code `unsupported` and the reason as its message instead of answering a state. A project that lacks what the prompt needs, such as the usage description of the `Info.plist` or the permission of the Android manifest, fails it the same way, with `data.missing`, which lists each missing requirement as `{kind, name, file, snippet}`, and the log tells once what the project lacks and how to add it. A platform where the owner has no native part fails the call with the code `noHandler`, as every call of that plugin.

### permissions.state(name)

Returns the platform call whose `await` gives the state of the permission `name`, as far as the platform tells it, without asking the person.

```lua
local async = require('async')
local permissions = require('permissions')
require('camera')

async.spawn(function()
    local state, failure = permissions.state('camera'):await()
    if state == 'prompt' then
        print('The app explains why it wants the camera before it asks.')
    elseif not state then
        print(failure.code, failure.message)
    end
end)
```

### permissions.request(name)

Asks the person for the permission `name` with the prompt of the system and returns the platform call whose `await` gives the state that the person left. The prompt shows only while the state is `'prompt'`, or `'unknown'` on the web, so a permission that the app holds answers `'granted'` at once and one that the person refused answers `'denied'` without a prompt. A request whose prompt the system did not show answers `'prompt'`, such as Safari, which asks only right after a tap or a click.

```lua
local async = require('async')
local permissions = require('permissions')
require('location')

async.spawn(function()
    local state, failure = permissions.request('backgroundLocation'):await()
    if failure and failure.data and failure.data.missing then
        print('The project lacks ' .. #failure.data.missing .. ' requirements: ' .. failure.message)
    else
        print(state and 'The location in the background is ' .. state .. '.' or failure.message)
    end
end)
```

### permissions.declare(id, names)

Declares the permissions `names` that the plugin `id` owns, the names of the `permissions` of its `plugin.json`, and returns the functions that the plugin offers to the app: `state(name)` and `request(name)`, which work as `permissions.state` and `permissions.request` for the permissions of that plugin alone. They take the name of one of its permissions, and a plugin with one permission takes it without a name. The Lua module of the plugin calls it when it loads, and a module that loads again, such as after a reload, declares its permissions again.

```lua
-- The Lua module of a plugin "scanner" that owns the permission "camera".
local permissions = require('permissions')

local scanner = {}
local permission = permissions.declare('scanner', {'camera'})

scanner.permission = permission.state
scanner.requestPermission = permission.request

return scanner
```

### Errors

| Message | When |
| --- | --- |
| `The permission "<name>" belongs to no plugin that the app loaded. Each plugin declares the permissions it owns in its "plugin.json", and its Lua module declares them when the app requires it.` | `permissions.state` or `permissions.request` takes a name that no Lua module of a plugin declared. It raises. |
| `The permission "<name>" belongs to the plugin "<other>", so the plugin "<id>" cannot declare it too. One plugin of an app owns each permission.` | A plugin declares a permission of another plugin. It raises. |
| `The plugin "<id>" owns the permissions "<a>" and "<b>", so "<id>.<method>" takes the name of one of them.` | A function of a plugin with several permissions takes no name. It raises. |
| `The plugin "<id>" owns no permission "<name>". It owns "<names>".` | A function of a plugin takes a name that the plugin does not own. It raises. |
| `No native handler is registered for "<id>.<method>".`, or `No page handler is registered for "<id>.<method>".` on the web | The owner has no native part on this platform, or its native part registered no permission. The call fails with the code `noHandler`. |
| `The plugin "<id>" registers no permission "<name>" on this platform.` | The native part of the owner registered other permissions but not this one. The call fails with the code `unsupported`. |
| The reason of the platform | The platform has no such capability, or the project lacks a requirement, which `data.missing` lists. The call fails with the code `unsupported`. |

## The permission of a plugin

A plugin that owns a permission declares its name in the `permissions` of its `plugin.json`, a `camelCase` name that no other plugin of the app declares, and lists `{"permissions": "1.0.0"}` in its `dependencies`. Its Lua module declares the permission with `permissions.declare`, each native part registers it, and every call of the plugin that uses the capability requires the permission first. A call that requires a permission that the person refused fails with the code `denied` and one of the two sentences of the refusal, the same on every platform:

- After `'denied'`: `The person has not allowed <capability>. Ask for it with "<id>.requestPermission('<name>')", which shows the prompt of the system while the system still asks, or the person allows it in the settings of the system.`
- After `'prompt'`, where the system did not show its prompt: `The system did not show its prompt for <capability>, so the app does not hold it yet. Ask for it again later with "<id>.requestPermission('<name>')".`

A permission that the project cannot serve fails the call with the code `unsupported`, the reason and `data.missing`, which lists each requirement that the project lacks as `{kind, name, file, snippet}`. A state of `'unknown'` lets the call go on, and the use of the capability asks the person.

### Apple platforms

The Swift of `apple/` joins the app target of every plugin, so the plugins that depend on it use its types directly. A `Permission` takes its name, the capability in words for the sentences of the refusal, the requirements of the project, which `HaylenRequirements` checks first, and two blocks: `state` reads the state and `request` shows the prompt of the system. Both run on the main actor and call their answer, a `Permission.Answer`, which is `@Sendable`, once, from any thread, with the reason for `.unsupported`, and an answer that comes twice keeps the first one and logs the mistake. The request runs only while the state is `.prompt`. `Permissions` lives on the main actor, where plugin classes load and the handlers of `register` run, so a plugin registers and requires its permissions there.

```swift
import AVFoundation

@objc(ScannerPlugin)
final class ScannerPlugin: NSObject, HaylenPlugin {
    struct Empty: Codable {}

    func load(with context: HaylenPluginContext) {
        Permissions.register(Permission(name: "camera", capability: "the camera", requirements: [.usageDescription("NSCameraUsageDescription")], state: { answer in
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            answer(status == .notDetermined ? .prompt : status == .authorized ? .granted : .denied, nil)
        }, request: { answer in
            AVCaptureDevice.requestAccess(for: .video) { granted in answer(granted ? .granted : .denied, nil) }
        }), on: context)

        context.register("scan") { (_: Empty) async throws -> Empty in
            try await Permissions.require("camera", on: context)
            return Empty()
        }
    }
}
```

| API | What it does |
| --- | --- |
| `Permission(name:capability:requirements:state:request:)` | A permission, whose `state` and `request` blocks are `@MainActor (@escaping Permission.Answer) -> Void`. |
| `Permission.Answer` | `@Sendable (Permission.State, String?) -> Void`, the answer of a block, which it calls once from any thread. |
| `Permission.State` | `.granted`, `.prompt`, `.denied`, `.unknown` or `.unsupported`. |
| `Permissions.register(_ permission: Permission, on context: HaylenPluginContext)` | Registers the permission. The first permission of a plugin registers the handlers `permission` and `requestPermission` on its context, which answer the name of the state or fail with the code `unsupported`. A name that the plugin registered before keeps its first permission, and the log names the mistake. |
| `Permissions.require(_ name: String, on context: HaylenPluginContext) async throws` | Asks for the permission where the app does not hold it and returns once the app holds it or the state is `.unknown`. Throws a `HaylenFailure` with the code `denied` and the sentence of the refusal, or `unsupported` with the reason and `missing` in its data, which fails the call of a handler. |
| `Permissions.refusal(_ answered: Permission.State, permission: Permission, plugin: String) -> String` | The sentence of the refusal after `.denied` or `.prompt`. |

### Android

The module of a plugin that lists `permissions` in its `dependencies` reaches the classes of `com.haylen.plugins.permissions`, since the Android backend of Haylen adds `api(project(":permissions"))` to it. A `Permission` takes its name, the capability in words and the permissions of the manifest that it needs, and a plugin overrides what differs: `unsupportedReason`, the sentence of a device without the capability, `required`, the permissions of the manifest on the Android that runs, `requested`, what the prompt asks for, `isGranted`, `stateWithoutPrompt`, the state where Android asks for nothing, and `prerequisite`, a permission that the person grants first in a prompt of its own, such as the location before the location in the background.

```kotlin
import android.Manifest
import com.haylen.plugins.permissions.Permission
import com.haylen.plugins.permissions.Permissions
import dev.haylen.HaylenPlugin
import dev.haylen.HaylenPluginContext

class ScannerPlugin : HaylenPlugin() {
    override fun onLoad(context: HaylenPluginContext) {
        Permissions.register(context, Permission("camera", "the camera", Manifest.permission.CAMERA))

        context.register("scan") { _, reply ->
            Permissions.require(context, "camera", reply) { reply.success(null) }
        }
    }
}
```

| API | What it does |
| --- | --- |
| `open class Permission(name: String, capability: String, vararg required: String)` | A permission, with the overridable members above. |
| `Permissions.register(context: HaylenPluginContext, permission: Permission)` | Registers the permission. The first permission of a plugin registers the handlers `permission` and `requestPermission` on its context, which answer the name of the state or fail with the code `unsupported`. Throws an `IllegalArgumentException` for a name that the plugin registered before. |
| `Permissions.require(context: HaylenPluginContext, name: String, reply: HaylenBridge.Reply, granted: Runnable)` | Runs `granted` on the main thread once the app holds the permission, after the prompt where the app does not hold it yet, or when no activity exists to show the prompt, which answers `unknown`. A refusal fails the call with the code `denied` and the sentence of the refusal, a manifest that lacks the permission fails it with `unsupported` and `data.missing`, and a `granted` that throws fails it with its error. Throws an `IllegalArgumentException` for a name that the plugin did not register. |
| `Permissions.refusal(plugin: String, permission: Permission, answered: String): String` | The sentence of the refusal after `denied` or `prompt`. |

The prompts show through one launcher of `RequestMultiplePermissions`, which the plugin registers with the Activity Result API of every activity under the key `haylen.permissions.request` before the activity starts. Requests wait in a queue and show one at a time. A request whose activity is recreated answers through the launcher of the new activity, and an activity that starts anew, after one that finished for good, answers the requests that waited with the state that the app holds, without a prompt.

### Web

The web module of a plugin imports the two functions, which the web backend of Haylen maps to the module of this plugin:

```js
import { registerPermission, requirePermission } from "haylen-plugin:permissions";

export default function load(context) {
    registerPermission(context, {
        name: "camera",
        capability: "the camera",
        needs: { secureContext: true, api: "navigator.mediaDevices.getUserMedia", permissionsPolicy: "camera" },
        query: "camera",
        request: async () => "granted",
    });

    context.register("scan", async () => {
        await requirePermission(context, "camera");
        return null;
    });
}
```

| Key | Meaning |
| --- | --- |
| `name` | The name of the permission. |
| `capability` | What the permission gives the app in words, for the sentences of the refusal. |
| `needs` | What the page needs for it, as `context.require` takes it: `secureContext`, `api` and `permissionsPolicy`. A page that lacks one answers `unsupported` with `missing`. |
| `unavailable` | A function that answers the sentence of a browser or a device without the capability, or nothing. |
| `query` | The name of the Permissions API that tells the state. |
| `unnamed` | The state where the browser does not know the name of `query`, `'unknown'` by default. |
| `check` | A function that tells the state instead of `query`. |
| `request` | The function that shows the prompt of the browser. |

The functions `check` and `request` answer the name of a state or `{state, message}`, and may be asynchronous. The handlers `<id>.permission` and `<id>.requestPermission` answer the name of the state, and fail a state of `unsupported` with that code, the message and `data.missing`. The function `registerPermission(context, permission)` throws for a permission without that shape and for a name that the plugin registered before, and `requirePermission(context, name)` returns a promise that rejects with the code `denied` and the sentence of the refusal, or `unsupported` with the reason and `data.missing`.

### Windows, Linux and the desktop player

The desktops have no native part of the plugin. The C++ library of `native/` of each plugin registers its own handlers `<id>.permission` and `<id>.requestPermission`, which answer the name of the state from the API of the system or fail with the code `unsupported` and the reason, and fails its other calls with the same codes and sentences of the refusal.

## Native API

| Method | Params | Answer |
| --- | --- | --- |
| `<id>.permission` | `{name}` | The name of the state: `"granted"`, `"prompt"`, `"denied"` or `"unknown"`. It reads the state and never asks. |
| `<id>.requestPermission` | `{name}` | The name of the state that the person left. It shows the prompt of the system only while the state is `prompt`, or `unknown` on the web. |

A state of `unsupported` fails the call with the code `unsupported`, the reason as its message and, for a project that lacks a requirement, `data.missing`, which lists `{kind, name, file, snippet}` for each one. A name that the plugin did not register on the platform fails the same way with `The plugin "<id>" registers no permission "<name>" on this platform.`.

## What each platform answers

| Platform | Answers |
| --- | --- |
| Apple platforms | The state that the block of the plugin reads from the API of the system. A project that lacks a requirement, such as a usage description of the `Info.plist`, fails with `unsupported` and `data.missing` before the system could end the app at the prompt. |
| Android | `granted` once the app holds every permission of the manifest that the permission needs, `prompt` before the first request, and `denied` once a request asked and Android no longer explains why the app wants it, which it does after a person refused twice. The plugin remembers which permissions it asked for across launches. A manifest that lacks a permission fails with `unsupported` and `data.missing`. |
| Web | The state of the Permissions API, or of the `check` of the plugin, and `unknown` where the browser tells nothing before it asks. A page that is not secure, or whose policy does not allow the feature, fails with `unsupported` and `data.missing`. |
| Windows, Linux and the desktop player | The answer of the library of `native/` of each plugin. |

## Platforms without the plugin

Windows and Linux have no native part of the plugin, which its `implementations` name `lua`, because the libraries of the desktops answer their own permissions. The Lua API works on every platform.

## Sample

The app in `sample/` references the plugin with `"path": ".."` and the local plugin `permission-states` of `sample/plugins/`, which owns a permission of every state: `held` is granted, `asked` is the permission of notifications, which shows the prompt of the system, `refused` is denied, `untold` is unknown and `absent` is unsupported. Each permission has a button that checks it, one that asks for it and one that uses it:

```sh
haylen app run sample --target macos
haylen app run sample --target ios-simulator
haylen app run sample --target android
haylen app run sample --target web
```

On Windows, Linux and the desktop player the local plugin has no native part, so every call fails with the code `noHandler`.

The UI tests of the sample press every button and read every answer of the log. On the iOS simulator they refuse the prompt of `asked`, see a later request answer the refusal without a prompt, and allow notifications in the Settings app. The system answers the notifications of an app that installs again within a day the way the person answered them before, so the prompt shows only on the first run of a day, and a later run turns off in the Settings app what the run before allowed. On the Android emulator they refuse the dialog once and allow it on a second request, which Android shows again after one refusal:

```sh
haylen test --ui sample --target ios-simulator
haylen test --ui sample --target android
```

On the web, `sample/ui-tests/web/permissions-check.mjs` drives the site in a headless Chrome over its debugging protocol. It presses the buttons of the mirror of the UI that the page keeps for screen readers, reads the log there, and sets the permission of notifications of the site to `prompt`, `denied` and `granted` in turn, as the settings of the site do. Build and serve the site, start Chrome with a debugging port and run the driver with that port and the address of the page:

```sh
haylen app build sample --target web
haylen serve <the products folder that the build names> --port 8765
"<Chrome>" --headless=new --remote-debugging-port=9222 --user-data-dir=<an empty folder> about:blank
node sample/ui-tests/web/permissions-check.mjs 9222 http://127.0.0.1:8765/
```

The driver prints every step as JSON and ends with the code 1 when a step did not hold.

## License

MIT, like Haylen.
