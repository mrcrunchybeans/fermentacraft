// android/app/build.gradle.kts
import java.util.Properties

val keystorePropsFile = rootProject.file("key.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) {
        load(keystorePropsFile.inputStream())
    }
}

/** Read version from local.properties (pubspec.yaml's `version: x.y.z+NN`) */
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream ->
        localProperties.load(stream)
    }
}

val flutterVersionCode: Int = localProperties.getProperty("flutter.versionCode")?.toInt() ?: 58
val flutterVersionName: String = localProperties.getProperty("flutter.versionName") ?: "2.0.0"

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fermentacraft"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.fermentacraft"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        // CRITICAL: these populate manifest version fields
        versionCode = flutterVersionCode
        versionName = flutterVersionName

        manifestPlaceholders["appAuthRedirectScheme"] =
            "com.googleusercontent.apps.747130944683-add6ufd63i82lh8ispnosi2ii3vu6hbn"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProps.getProperty("storeFile") ?: ""
            // Only configure signing if storeFile is a valid path on this platform
            // Windows paths contain a colon after the drive letter (e.g., C:\)
            if (storeFilePath.isNotBlank() && !storeFilePath.contains(":")) {
                val file = rootProject.file(storeFilePath)
                if (file.exists()) {
                    storeFile = file
                    storePassword = keystoreProps.getProperty("storePassword")
                    keyAlias = keystoreProps.getProperty("keyAlias")
                    keyPassword = keystoreProps.getProperty("keyPassword")
                }
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Only sign release if signing config is properly set up (no Windows paths)
            val storeFilePath = keystoreProps.getProperty("storeFile") ?: ""
            if (storeFilePath.isNotBlank() && !storeFilePath.contains(":")) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Not required for our edge-to-edge approach, but harmless if you keep it
    implementation("androidx.activity:activity:1.10.1")
}
