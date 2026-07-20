plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "br.com.azulzin.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "br.com.azulzin.app"
        minSdk = 28          // Hotwire Native Android floor (.plans/mobile/03)
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        debug {
            // Emulator loopback; cleartext allowed ONLY via the debug network security config.
            buildConfigField("String", "BASE_URL", "\"http://10.0.2.2:3000\"")
        }
        release {
            buildConfigField("String", "BASE_URL", "\"https://app.azulzin.com.br\"")
            isMinifyEnabled = false
        }
    }

    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("dev.hotwire:core:1.2.5")
    implementation("dev.hotwire:navigation-fragments:1.2.5")
    implementation("com.google.android.material:material:1.12.0")
}
