import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// key.properties 파일 읽기
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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
        // Play Console에서 모바일과 Wear OS가 별도 페이지로 관리되므로
        // 버전 코드 충돌을 방지하기 위해 오프셋(1000) 추가
        // 모바일: 1, 2, 3... → Wear OS: 1001, 1002, 1003...
        // versionName은 모바일과 동일하게 유지 (사용자에게 보이는 버전)
        versionCode = 1002  // 모바일 versionCode(2) + 1000
        versionName = "1.0.1"
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"]?.toString() ?: ""
                keyPassword = keystoreProperties["keyPassword"]?.toString() ?: ""
                val keystoreFileName = keystoreProperties["storeFile"]?.toString() ?: ""
                storeFile = if (keystoreFileName.isNotEmpty()) {
                    rootProject.file(keystoreFileName)
                } else {
                    file("")
                }
                storePassword = keystoreProperties["storePassword"]?.toString() ?: ""
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
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

