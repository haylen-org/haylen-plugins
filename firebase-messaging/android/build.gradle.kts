// Android library module of the Firebase Messaging plugin. The tooling copies it into `plugins/firebase-messaging` of the Android project that it generates for an app, which depends on it. The `haylen-plugins` library brings the plugin API of the `haylen` library and the provider that loads the plugin when the app process starts, `haylen-links` the activity that the taps of notifications start, and the Firebase bill of materials picks the versions of the Firebase libraries.
plugins {
    id("com.android.library")
}

android {
    namespace = "com.haylen.plugins.firebasemessaging"
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
    implementation("dev.haylen:haylen-links:$haylenEngineVersion")
    implementation(platform("com.google.firebase:firebase-bom:35.1.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-installations")
}
