import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
}

// Upload keystore lives OUTSIDE git (native/android/keystore.properties + upload-keystore.jks,
// both gitignored) — Play App Signing holds the real signing key, this one is replaceable.
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "br.com.azulzin.app"
    compileSdk = 36          // Play's annual floor: API 36 required for new apps from Aug 31, 2026

    defaultConfig {
        applicationId = "br.com.azulzin.app"
        minSdk = 28          // Hotwire Native Android floor (.plans/mobile/03)
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        create("release") {
            if (keystoreProps.isNotEmpty()) {
                storeFile = rootProject.file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
            }
        }
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
            if (keystoreProps.isNotEmpty()) signingConfig = signingConfigs.getByName("release")
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
