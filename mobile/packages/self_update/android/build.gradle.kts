// Java only, so it needs no Kotlin Gradle plugin.
group = "com.jobsummit.self_update"
version = "1.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.jobsummit.self_update"
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
