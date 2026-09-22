pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // Bumped from 2.2.20 for the LiteRT-LM local provider:
    // com.google.ai.edge.litertlm:litertlm-android:0.17.1's own classes are
    // published with Kotlin 2.4.0 metadata, which a 2.2.x compiler cannot
    // read at all ("compiled with an incompatible version of Kotlin") --
    // confirmed by an actual failing compile, not assumed. Pinned to the
    // exact version litertlm-android was built with rather than the newest
    // available Kotlin release (2.4.20), per the "minimal change" rule.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
