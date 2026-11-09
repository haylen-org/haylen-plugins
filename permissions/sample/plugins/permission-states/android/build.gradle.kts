// Android library module of the local plugin of the sample. The tooling copies it into `plugins/permission-states/` of the Android project that it generates for the sample, and adds `api(project(":permissions"))` to it, since the plugin lists `permissions` in its `dependencies`.
plugins {
    id("com.android.library")
}

android {
    namespace = "com.haylen.plugins.permissionstates"
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
}
