plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Keep these bounds and the formula aligned with tool/android-version.ps1.
fun compactAndroidVersionCode(versionName: String, build: Int): Int {
    require(Regex("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)").matches(versionName)) {
        "Android version name must be major.minor.patch."
    }
    val parts = versionName.split(".").map { it.toLongOrNull() }
    require(parts.all { it != null }) { "Android version component is too large." }
    val (major, minor, patch) = parts.map { requireNotNull(it) }
    require(major <= 209999 && minor <= 9 && patch <= 9 && build in 1..99) {
        "Android compact version requires major <= 209999, minor/patch <= 9 and build in 1..99."
    }
    return (major * 10000 + minor * 1000 + patch * 100 + build).toInt()
}

require(project.findProperty("force-version-code-ignoring-abi").toString() == "true") {
    "BiliSail requires force-version-code-ignoring-abi=true to preserve compact version codes."
}

val releaseStorePath = System.getenv("ANDROID_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val releaseSigningValues = listOf(
    releaseStorePath, releaseStorePassword, releaseKeyAlias, releaseKeyPassword,
)
val hasReleaseSigning = releaseSigningValues.all { !it.isNullOrBlank() }
val hasAnyReleaseSigning = releaseSigningValues.any { !it.isNullOrBlank() }
val usePreviewSigning = System.getenv("ANDROID_PREVIEW_SIGNING") == "true"

if (hasAnyReleaseSigning && !hasReleaseSigning) {
    throw GradleException("Android release signing environment is incomplete.")
}
if (usePreviewSigning && hasAnyReleaseSigning) {
    throw GradleException("Preview builds must not receive the Android release signing key.")
}

android {
    namespace = "dev.bilisail.bilisail"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // BiliSail application identity, shared with the MainActivity namespace.
        applicationId = "dev.bilisail.bilisail"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Flutter still receives the raw +build number; encode exactly once here.
        versionCode = compactAndroidVersionCode(flutter.versionName, flutter.versionCode)
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(requireNotNull(releaseStorePath))
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (usePreviewSigning) "debug" else "release")
        }
    }
}

// Debug builds need no release credentials; release builds must never silently
// switch to a new debug key when the fixed signing configuration is missing.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (!hasReleaseSigning && !usePreviewSigning) {
            throw GradleException("Android release signing is required. Configure ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD.")
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

