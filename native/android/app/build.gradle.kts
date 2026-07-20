plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
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
            // localhost (via `adb reverse tcp:3000 tcp:3000`), NOT 10.0.2.2: getUserMedia
            // (chat mic) needs a trustworthy origin and Chromium only whitelists localhost.
            // Cleartext allowed ONLY via the debug network security config.
            buildConfigField("String", "BASE_URL", "\"http://localhost:3000\"")
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
    implementation("androidx.biometric:biometric:1.1.0")
    // google-services plugin route (04 §3): app/google-services.json is required at
    // build time; the BoM pins the firebase-messaging version.
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-messaging")
}
