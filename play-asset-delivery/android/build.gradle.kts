// Android library module of the Play Asset Delivery plugin. The tooling copies it into `plugins/play-asset-delivery` of the Android project that it generates for an app, which depends on it. The `haylen-plugins` library brings the plugin API of the `haylen` library and the provider that loads the plugin when the app process starts.
plugins {
    id("com.android.library")
}

android {
    namespace = "com.haylen.plugins.playassetdelivery"
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
    implementation("com.google.android.play:asset-delivery:2.3.0")
    // The library of Play brings an older WorkManager, whose database the shrinking of a release build removes, so the module takes the current one.
    implementation("androidx.work:work-runtime:2.12.0")
}
