import java.util.Base64
import java.io.File
import com.google.gms.googleservices.GoogleServicesTask
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
    id("com.google.firebase.crashlytics") apply false
}

val dartDefineValues = (findProperty("dart-defines") as? String).orEmpty()
    .split(",")
    .filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
val appEnvironment = dartDefineValues
    .lastOrNull { it.startsWith("APP_ENV=") }
    ?.substringAfter("=")
    ?: "test"
val dartDefines = dartDefineValues.associate { value ->
    value.substringBefore("=") to value.substringAfter("=", "")
}
val isProductionEnvironment = appEnvironment == "production"
val productionApplicationId = System.getenv("ANDROID_APPLICATION_ID")?.trim().orEmpty()
val firebaseConfigPath = System.getenv("ANDROID_FIREBASE_CONFIG_PATH")?.trim().orEmpty()
val firebaseConfigFile = firebaseConfigPath.takeIf { it.isNotEmpty() }?.let(::file)
val hasFirebaseConfig = firebaseConfigFile?.isFile == true
val projectDebugKeystore = rootProject.file(
    "../../../.dart_tool/android-test-signing/cardvault-debug.keystore",
)
val keytoolExecutable = File(
    System.getProperty("java.home"),
    "bin/keytool${if (System.getProperty("os.name").startsWith("Windows", ignoreCase = true)) ".exe" else ""}",
)
if (isProductionEnvironment && productionApplicationId.isEmpty()) {
    error("ANDROID_APPLICATION_ID is required for an Android production build.")
}
if (
    isProductionEnvironment &&
    gradle.startParameter.taskNames.any { it.contains("debug", ignoreCase = true) }
) {
    error("Android production configuration must use a release build and external signing.")
}
if (isProductionEnvironment && !hasFirebaseConfig) {
    error(
        "ANDROID_FIREBASE_CONFIG_PATH must point to an external google-services.json " +
            "for an Android production build.",
    )
}
if (isProductionEnvironment) {
    val requiredProductionDefines = listOf(
        "ANDROID_PLAY_CLOUD_PROJECT_NUMBER",
        "GOOGLE_SERVER_CLIENT_ID",
    )
    val missingDefines = requiredProductionDefines.filter {
        dartDefines[it].isNullOrBlank()
    }
    if (missingDefines.isNotEmpty()) {
        error(
            "Missing Android production dart-defines: ${missingDefines.joinToString(", ")}.",
        )
    }
}

if (hasFirebaseConfig) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
    tasks.withType<GoogleServicesTask>().configureEach {
        googleServicesJsonFiles.set(listOf(firebaseConfigFile!!))
    }
}

val prepareProjectDebugKeystore = tasks.register<Exec>("prepareProjectDebugKeystore") {
    group = "build setup"
    description = "Creates the project-local Android debug keystore when absent."
    outputs.file(projectDebugKeystore)
    onlyIf { !projectDebugKeystore.isFile }
    doFirst { projectDebugKeystore.parentFile.mkdirs() }
    commandLine(
        keytoolExecutable.absolutePath,
        "-genkeypair",
        "-v",
        "-keystore",
        projectDebugKeystore.absolutePath,
        "-storepass",
        "android",
        "-alias",
        "androiddebugkey",
        "-keypass",
        "android",
        "-dname",
        "CN=Android Debug,O=CardVault Test,C=US",
        "-keyalg",
        "RSA",
        "-keysize",
        "2048",
        "-validity",
        "10000",
    )
}

android {
    namespace = "dev.kando.cardvault.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = if (isProductionEnvironment) {
            productionApplicationId
        } else {
            "com.kando.kandoApp.beta"
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["networkSecurityConfig"] = if (!isProductionEnvironment) {
            "@xml/network_security_config_test"
        } else {
            "@xml/network_security_config"
        }
    }

    signingConfigs.getByName("debug") {
        keyAlias = "androiddebugkey"
        keyPassword = "android"
        storeFile = projectDebugKeystore
        storePassword = "android"
    }

    if (isProductionEnvironment) {
        val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")?.trim().orEmpty()
        val keyAliasValue = System.getenv("ANDROID_KEY_ALIAS")?.trim().orEmpty()
        val keyPasswordValue = System.getenv("ANDROID_KEY_PASSWORD").orEmpty()
        val storePasswordValue = System.getenv("ANDROID_STORE_PASSWORD").orEmpty()
        if (listOf(keystorePath, keyAliasValue, keyPasswordValue, storePasswordValue).any { it.isEmpty() }) {
            error(
                "ANDROID_KEYSTORE_PATH, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD, and " +
                    "ANDROID_STORE_PASSWORD are required for an Android production build.",
            )
        }
        signingConfigs {
            create("release") {
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
                storeFile = file(keystorePath)
                storePassword = storePasswordValue
            }
        }
    }

    buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (isProductionEnvironment) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

tasks.configureEach {
    if (name == "preDebugBuild" || name == "validateSigningDebug") {
        dependsOn(prepareProjectDebugKeystore)
    }
}

dependencies {
    implementation(files("libs/onnxruntime-minimal-1.23.0.aar"))
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.android.play:integrity:1.5.0")
}

flutter {
    source = "../.."
}
