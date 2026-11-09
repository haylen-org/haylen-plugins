// Android library module of the Media Session plugin. The tooling copies it into `plugins/media-session` of the Android project that it generates for an app, which depends on it. The `haylen-plugins` library brings the plugin API of the `haylen` library, AndroidX Core and the provider that loads the plugin when the app process starts.
plugins {
    id("com.android.library")
}

android {
    namespace = "com.haylen.plugins.mediasession"
    compileSdk {
        version = release(37) {
            minorApiLevel = 2
        }
    }

    defaultConfig {
        minSdk = 27
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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

    // The decoding of the artwork needs the bitmaps of Android, which its tests check on a device or the emulator.
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
