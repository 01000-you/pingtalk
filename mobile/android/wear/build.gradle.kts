plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    // NOTE: Play Store "워치 지원 앱" 흐름을 위해 (최종적으로) 폰 앱과 동일 applicationId 유지.
    namespace = "com.pingtalk.app.wear"
    // wear 모듈은 Flutter 플러그인을 쓰지 않으므로 값을 명시
    compileSdk = 35

    defaultConfig {
        applicationId = "com.pingtalk.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.0.1"
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

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")

    // Wear OS / Data Layer
    implementation("com.google.android.gms:play-services-wearable:18.2.0")

    // 단순 UI용
    implementation("com.google.android.material:material:1.12.0")
}

