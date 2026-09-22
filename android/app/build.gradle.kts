import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.psyche.kelivo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Moru ships as an independent personal app under its own stable identity.
        applicationId = "com.mishaqp.moru"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Moru ships one APK for Android arm64. Keep Flutter, AGP and CMake aligned.
        ndk {
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
        unitTests.isIncludeAndroidResources = true
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

val requiredProotLibs = listOf(
    "arm64-v8a/libproot_exec.so",
    "arm64-v8a/libproot_loader.so",
    "arm64-v8a/libtalloc.so",
    "arm64-v8a/libandroid-shmem.so",
)

tasks.register<Exec>("fetchProot") {
    val repoRoot = rootProject.projectDir.parentFile
    commandLine("bash", repoRoot.resolve("tool/fetch_proot.sh").absolutePath)
    workingDir = repoRoot
    onlyIf {
        val jniLibs = layout.projectDirectory.dir("src/main/jniLibs")
        requiredProotLibs.any { name ->
            val so = jniLibs.file(name).asFile
            !so.isFile || so.length() == 0L
        }
    }
}

tasks.whenTaskAdded {
    if (name == "preBuild") {
        dependsOn("fetchProot")
    }
}
tasks.findByName("preBuild")?.dependsOn("fetchProot")

dependencies {
    implementation("androidx.browser:browser:1.9.0")
    implementation("org.tukaani:xz:1.10")
    // Pinned exact release -- never latest.release/a floating range. Verified
    // against Google Maven's own maven-metadata.xml (docs/litert-lm-progress.md).
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.17.1")
    // Required for core library desugaring (used by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}
