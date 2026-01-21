plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "com.example.aogra_study"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.aogra_study"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        
        // 配置jni库路径
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    
    // 配置jni库目录（实际目录为 app/jniLibs）
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("jniLibs")
        }
    }
    
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.appcompat)
    implementation(libs.material)
    implementation(libs.activity)
    implementation(libs.constraintlayout)
    testImplementation(libs.junit)
    androidTestImplementation(libs.ext.junit)
    androidTestImplementation(libs.espresso.core)
    // 添加Agora本地AAR库依赖
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
    // 添加Agora JAR库依赖
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar"))))
}