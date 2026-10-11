import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.tasks.compile.JavaCompile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing config from android/key.properties (kept out of git).
// If it's absent (e.g. a dev machine), we fall back to debug signing so that
// `flutter run --release` still works locally.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.failas.expnd"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (and other plugins using java.time)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.failas.expnd"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String).let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // Personal build (tool/build_personal_apk.sh): layers a manifest that
    // grants INTERNET for the optional cloud coach. Off unless the variable
    // is set, so store and normal builds stay offline.
    if (System.getenv("EXPND_PERSONAL_BUILD") == "1") {
        sourceSets.getByName("release").manifest.srcFile(
            "src/personal/AndroidManifest.xml"
        )
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No release keystore present — debug-sign so local release
                // builds run. DO NOT upload this variant to the Play Store.
                signingConfigs.getByName("debug")
            }
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

dependencies {
    // Enables core library desugaring required by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Bundled model keeps receipt scanning available without a network request.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}

// integration_test is intentionally a dev dependency, but older Flutter
// tooling still emits it in GeneratedPluginRegistrant.java for release builds.
// Remove only that optional registration before compiling release variants;
// debug/integration-test builds keep the plugin available.
tasks.withType<JavaCompile>().configureEach {
    if (name.contains("Release", ignoreCase = true)) {
        doFirst {
            val registrant = project.file(
                "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"
            )
            if (registrant.exists()) {
                val source = registrant.readText()
                val cleaned = source.replace(
                    Regex("""(?s)\n\s*try \{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\} catch \(Exception e\) \{\s*Log\.e\(TAG, "Error registering plugin integration_test[^;]*;\s*\}\s*"""),
                    "\n"
                )
                if (cleaned != source) registrant.writeText(cleaned)
            }
        }
    }
}
