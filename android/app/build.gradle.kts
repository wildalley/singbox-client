plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wildalley.singbox_client"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.wildalley.singbox_client"
        // libbox needs API 24+ for the VpnService/file APIs it relies on.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion

        ndk {
            // libs/libbox.aar is built for arm64 only, so anything else would
            // ship without libbox.so. This only constrains libraries AGP itself
            // packages, though — Flutter's libflutter.so/libapp.so arrive as a
            // Maven dependency and ignore it, so a plain `flutter build apk`
            // still produces armeabi-v7a and x86_64 splits that crash on start.
            // Pass `--target-platform android-arm64` to keep them out; see README.
            abiFilters += "arm64-v8a"
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // libbox's Java bindings are reached by name from Go through JNI, so
            // code shrinking risks stripping live classes. Resource shrinking must
            // be disabled alongside it (AGP rejects one without the other).
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            // libbox.so is large; keeping it uncompressed lets the loader mmap it.
            useLegacyPackaging = false
        }
    }
}

dependencies {
    implementation(files("libs/libbox.aar"))
    implementation("androidx.core:core-ktx:1.15.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
