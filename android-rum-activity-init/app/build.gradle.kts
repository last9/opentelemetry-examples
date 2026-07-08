import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

fun localProp(key: String, default: String): String = localProperties.getProperty(key) ?: default

android {
    namespace = "io.last9.rumactivityinit"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.last9.rumactivityinit"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        buildConfigField("String", "LAST9_BASE_URL", "\"${localProp("last9.baseUrl", "https://otlp-ext-aps1.last9.io/v1/otlp/organizations/<org>")}\"")
        buildConfigField("String", "LAST9_CLIENT_TOKEN", "\"${localProp("last9.clientToken", "<your-client-token>")}\"")
        buildConfigField("String", "LAST9_ORIGIN", "\"${localProp("last9.origin", "https://app.last9.io")}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }
}

dependencies {
    implementation(libs.okhttp)
    implementation("io.last9:rum-android:${localProp("last9.rumSdkVersion", "0.9.0")}")
}
