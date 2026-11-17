plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// This opt-in is only for private engineering AAB preparation. No CI key exists.
val unsignedBundle = System.getenv("SANJAAL_UNSIGNED_BUNDLE") == "1"
if (unsignedBundle && gradle.startParameter.taskNames.none { it.contains("bundle", ignoreCase = true) }) {
    throw GradleException("Unsigned release mode is restricted to bundle tasks")
}

android {
    namespace = "au.fintex.sanjaal"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "au.fintex.sanjaal"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // One version code for APK and AAB. gradle.properties explicitly disables
        // Flutter's per-ABI offset so Play and sideload updates cannot diverge.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (unsignedBundle) {
            // Flutter's target-platform flag limits its own binaries, not plugin
            // AAR libraries. Do not advertise incomplete ARMv7/x86_64 support.
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }

    buildTypes {
        release {
            // Ordinary APKs are CI-only debug-signed previews. The explicit bundle
            // path is unsigned and must pass the offline pinned-key finalizer.
            signingConfig = if (unsignedBundle) null else signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Official Google Play full-build updates. No third-party code-push engine.
dependencies {
    implementation("com.google.android.play:app-update:2.1.0")
}
