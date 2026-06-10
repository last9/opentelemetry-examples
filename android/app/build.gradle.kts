import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

// Read Last9 RUM credentials from local.properties (git-ignored).
// Copy local.properties.example to local.properties and fill in your values.
val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

fun localProp(key: String, default: String): String =
    (localProperties.getProperty(key) ?: default)

android {
    namespace = "io.last9.rumexample"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.last9.rumexample"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        // Last9 RUM credentials surfaced from local.properties into BuildConfig.
        buildConfigField(
            "String",
            "LAST9_BASE_URL",
            "\"${localProp("last9.baseUrl", "https://otlp-ext-aps1.last9.io/v1/otlp/organizations/<org>")}\"",
        )
        buildConfigField(
            "String",
            "LAST9_CLIENT_TOKEN",
            "\"${localProp("last9.clientToken", "<your-client-token>")}\"",
        )
        buildConfigField(
            "String",
            "LAST9_ORIGIN",
            "\"${localProp("last9.origin", "https://app.last9.io")}\"",
        )
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
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.okhttp)

    // Last9 RUM Android SDK — resolved from the CDN Maven repo declared in
    // settings.gradle.kts (https://cdn.last9.io/rum-sdk/android/maven/).
    // Version comes from local.properties (last9.rumSdkVersion); default 0.7.1.
    implementation("io.last9:rum-android:${localProp("last9.rumSdkVersion", "0.7.1")}")

    debugImplementation(libs.androidx.ui.tooling)
}
