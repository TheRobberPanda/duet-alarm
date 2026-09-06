plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.duet.alarm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.duet.alarm"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // A Spotify Client ID is public by design (like the Supabase
        // publishable key); it is passed in rather than committed only so a
        // fork does not silently ship someone else's quota. Absent, it is ""
        // and the Spotify feature is simply off.
        buildConfigField(
            "String",
            "SPOTIFY_CLIENT_ID",
            "\"${project.findProperty("spotify.clientId") ?: ""}\""
        )
    }

    // Enabled so SpotifyConfig can read the Client ID that was passed in at
    // build time rather than committed. Off by default in AGP 8.
    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Spotify's App Remote SDK is not on Maven: it is an .aar downloaded from the
// Spotify developer dashboard after accepting their terms, which this repo
// cannot do for you. So it is optional. Drop
// `app/libs/spotify-app-remote-release.aar` in and the real implementation is
// compiled; without it the stub is, and Spotify alarms fall back to their
// tone. Two source sets, one API -- see SpotifyRemote.kt in each.
val spotifyAar = file("libs/spotify-app-remote-release.aar")

android.sourceSets.getByName("main").kotlin.srcDir(
    if (spotifyAar.exists()) "src/spotify/kotlin" else "src/nospotify/kotlin"
)

dependencies {
    if (spotifyAar.exists()) {
        implementation(files(spotifyAar))
        // App Remote needs these at runtime; they ARE on Maven.
        implementation("com.google.code.gson:gson:2.10.1")
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
