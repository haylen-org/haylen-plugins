// Android library module of the AdMob plugin. The tooling copies it into `plugins/admob` of the Android project that it generates for an app, which depends on it. The `haylen-plugins` library brings the plugin API of the `haylen` library and the provider that loads the plugin when the app process starts.
plugins {
    id("com.android.library")
}

android {
    namespace = "com.haylen.plugins.admob"
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
    implementation("com.google.android.gms:play-services-ads:25.5.0")
    implementation("com.google.android.ump:user-messaging-platform:4.0.0")
}
