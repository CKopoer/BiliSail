import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// One persistent identity for local Debug/Profile/Release device validation.
val isDevelopmentBuild = providers.gradleProperty("bilisailDevelopmentBuild").map {
    require(it == "true" || it == "false") { "bilisailDevelopmentBuild must be true or false." }
    it.toBoolean()
}.getOrElse(false)

// Keep these bounds and the formula aligned with tool/android-version.ps1.
fun compactAndroidVersionCode(versionName: String, build: Int): Int {
    require(Regex("(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)").matches(versionName)) {
        "Android version name must be major.minor.patch."
    }
    val parts = versionName.split(".").map { it.toLongOrNull() }
    require(parts.all { it != null }) { "Android version component is too large." }
    val (major, minor, patch) = parts.map { requireNotNull(it) }
    require(major <= 209999 && minor <= 9 && patch <= 9 && build in 0..99) {
        "Android compact version requires major <= 209999, minor/patch <= 9 and build in 0..99."
    }
    val code = (major * 10000 + minor * 1000 + patch * 100 + build).toInt()
    require(code > 0) { "Android versionCode must be positive; use a nonzero version component." }
    return code
}

require(project.findProperty("force-version-code-ignoring-abi").toString() == "true") {
    "BiliSail requires force-version-code-ignoring-abi=true to preserve compact version codes."
}

// Flutter normalizes Android --build-number 0 to 1. Packaging already passes
// the original version for the app's update checker; preserve that same value.
val releaseVersion = (project.findProperty("dart-defines") as? String)
    ?.split(",")
    ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    ?.singleOrNull { it.startsWith("BILISAIL_RELEASE_VERSION=") }
    ?.substringAfter("=")
val originalBuildNumber = releaseVersion?.let {
    require(Regex("(0|[1-9][0-9]*)\\.[0-9]\\.[0-9]\\+(0|[1-9][0-9]?)").matches(it)) {
        "BILISAIL_RELEASE_VERSION must use the compact Android version bounds."
    }
    require(it.substringBefore("+") == flutter.versionName) {
        "BILISAIL_RELEASE_VERSION must match Flutter's build name."
    }
    it.substringAfter("+").toInt()
} ?: flutter.versionCode

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
if (isDevelopmentBuild && hasAnyReleaseSigning) {
    throw GradleException("Development builds must not receive the Android release signing key.")
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
        applicationIdSuffix = if (isDevelopmentBuild) ".test" else null
        manifestPlaceholders["bilisailAppLabel"] = if (isDevelopmentBuild) "BiliSail 测试版" else "BiliSail"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Encode the original +build number exactly once, including zero.
        versionCode = compactAndroidVersionCode(flutter.versionName, originalBuildNumber)
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
            signingConfig = signingConfigs.getByName(if (isDevelopmentBuild || usePreviewSigning) "debug" else "release")
        }
    }
}

// Debug builds need no release credentials; release builds must never silently
// switch to a new debug key when the fixed signing configuration is missing.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (!isDevelopmentBuild && !hasReleaseSigning && !usePreviewSigning) {
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

dependencies {
    implementation("androidx.media3:media3-exoplayer:1.9.2")
}

