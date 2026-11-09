// Android library module of the Permissions plugin. The tooling copies it into `plugins/permissions/` of the Android project that it generates for an app, and every module of a plugin that lists `permissions` in its `dependencies` reaches its classes through `api(project(":permissions"))`, which the tooling writes. The `haylen-plugins` library brings the plugin API of the `haylen` library and the provider that loads the plugin when the app process starts.
plugins {
    id("com.android.library")
}

android {
    namespace = "com.haylen.plugins.permissions"
    compileSdk {
        version = release(37) {
            minorApiLevel = 2
        }
    }

    defaultConfig {
        minSdk = 27
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// The Android project of the app gives every module the engine version it builds with.
val haylenEngineVersion = extra["haylenEngineVersion"] as String

dependencies {
    implementation("dev.haylen:haylen-plugins:$haylenEngineVersion")

    // The queue of the prompts is plain logic, which its tests check on the JVM.
    testImplementation("junit:junit:4.13.2")
}
