import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ключ и пароли для подписи релизной сборки хранятся вне репозитория (ADR 0005,
// docs/decisions/0005-android-release-signing.md). Путь к properties-файлу с
// этими данными Gradle берёт из переменной окружения ZUNO_KEYSTORE_PROPERTIES;
// сам файл и пароли в репозитории не появляются.
val zunoKeystorePropertiesPath: String? = System.getenv("ZUNO_KEYSTORE_PROPERTIES")
val zunoKeystoreProperties = Properties()
var zunoHasKeystoreProperties = false
if (zunoKeystorePropertiesPath != null) {
    val propertiesFile = File(zunoKeystorePropertiesPath)
    if (propertiesFile.exists()) {
        try {
            FileInputStream(propertiesFile).use { zunoKeystoreProperties.load(it) }
            zunoHasKeystoreProperties = true
        } catch (e: Exception) {
            zunoHasKeystoreProperties = false
        }
    }
}

android {
    namespace = "com.tonyvinsenty.zuno"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tonyvinsenty.zuno"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (zunoHasKeystoreProperties) {
            create("release") {
                storeFile = file(zunoKeystoreProperties.getProperty("storeFile"))
                storePassword = zunoKeystoreProperties.getProperty("storePassword")
                keyAlias = zunoKeystoreProperties.getProperty("keyAlias")
                keyPassword = zunoKeystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (zunoHasKeystoreProperties) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Релизная сборка без ключа подписи не имеет смысла (ADR 0005): обновление на
// телефоне не встанет поверх ранее установленной версии. Поэтому сборка
// останавливается с понятным сообщением, но только если реально запрошены
// задачи сборки релиза (assembleRelease/bundleRelease и подобные) — отладочные
// и профильные сборки (flutter run, flutter build apk --debug, тесты) должны
// продолжать работать без переменной окружения ZUNO_KEYSTORE_PROPERTIES.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { task ->
        task.name.contains("Release") &&
            (task.name.startsWith("assemble") ||
                task.name.startsWith("bundle") ||
                task.name.startsWith("package"))
    }
    if (buildingRelease && !zunoHasKeystoreProperties) {
        throw GradleException(
            "Ключ подписи не найден: задайте переменную окружения " +
                "ZUNO_KEYSTORE_PROPERTIES, см. docs/how-to-android-release.md"
        )
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
