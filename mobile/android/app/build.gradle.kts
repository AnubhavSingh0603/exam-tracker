// App module build script, following the template of Flutter 3.47 / AGP 9 / Kotlin 2.4.
// (No `kotlin-android` plugin line and `kotlin { compilerOptions }` instead of `kotlinOptions`:
// both are required by this toolchain.)
import com.android.build.api.variant.FilterConfiguration
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Release signing -----------------------------------------------------------
// android/key.properties (git-ignored) points at the production keystore.
// Outside Google Play there is no "Play App Signing": THIS key is the app's identity
// forever. Lose it and existing users can never receive another update.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (isReleaseTask && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "android/key.properties is missing. Release builds must be signed with the production " +
            "keystore (see mobile/RELEASING.md); a debug-signed APK can never update a real install.",
    )
}

android {
    namespace = "com.examtracker.exam_tracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by ota_update 7.x.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.examtracker.exam_tracker"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    // direct: GitHub Releases / website APKs, with the in-app updater.
    // store:  Indus Appstore / Galaxy Store; the store updates the app, so the
    //         updater is disabled in Dart and REQUEST_INSTALL_PACKAGES is removed
    //         (src/store/AndroidManifest.xml).
    flavorDimensions += "distribution"
    productFlavors {
        create("direct") { dimension = "distribution" }
        create("store") { dimension = "distribution" }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// --- Version codes -------------------------------------------------------------
// Intended: <pubspec build number> × 10 + ABI digit. What the published APKs really
// get (checked with aapt2 on releases 0.7.0–0.10.0): universal = build × 10, but the
// split APKs also get Flutter's ABI × 1000 on top (arm64 0.9.2 = 2121, v7a = 1121).
// Both still rise with every release, so updates install; do NOT "fix" this to
// smaller numbers, or phones holding 2xxx codes would refuse the next update as a
// downgrade. The app reads the release as (code % 1000) ~/ 10 (update_service.dart).
// Verify with: aapt2 dump badging <apk> | head -1
val abiDigit = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { output ->
            val abi = output.filters.find { it.filterType == FilterConfiguration.FilterType.ABI }?.identifier
            output.versionCode.set(flutter.versionCode * 10 + (abiDigit[abi] ?: 0))
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
