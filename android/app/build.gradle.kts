plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.user_interface"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.user_interface"
        minSdk = 24

        // ✅ targetSdk 可以先跟著 36（通常沒問題）
        //    如果你怕 runtime 行為改變，targetSdk 也可以先留 35
        targetSdk = 36

        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // ★★★ 新增下面這一行 ★★★
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ... 其他原本的依賴 ...

    // 【請加入這行】加入 ML Kit 中文辨識模型
    // 注意：要有括號和雙引號
    // ★★★ 新增下面這一行 ★★★
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}