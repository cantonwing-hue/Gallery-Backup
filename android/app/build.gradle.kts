plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val vaultDebugStoreFile = providers.environmentVariable("VAULT_DEBUG_STORE_FILE").orNull
val vaultDebugStorePassword = providers.environmentVariable("VAULT_DEBUG_STORE_PASSWORD").orNull

require(vaultDebugStoreFile.isNullOrBlank() == vaultDebugStorePassword.isNullOrBlank()) {
    "Set both VAULT_DEBUG_STORE_FILE and VAULT_DEBUG_STORE_PASSWORD for persistent signing."
}

android {
    namespace = "com.example.cloud_photo_vault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.cloud_photo_vault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (!vaultDebugStoreFile.isNullOrBlank() && !vaultDebugStorePassword.isNullOrBlank()) {
        signingConfigs.getByName("debug") {
            storeFile = file(vaultDebugStoreFile)
            storeType = "PKCS12"
            storePassword = vaultDebugStorePassword
            keyAlias = "vault-debug"
            keyPassword = vaultDebugStorePassword
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
