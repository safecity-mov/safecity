import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Lus avant le bloc `android` qui s'en sert : un script Kotlin initialise ses propriétés
// dans l'ordre du fichier.
fun lirePropriétés(nom: String): Properties = Properties().apply {
    val fichier = rootProject.file(nom)
    if (fichier.exists()) fichier.inputStream().use { load(it) }
}

// L'identité publiée de l'app, versionnée et partagée avec deploy/ (voir app.properties).
val appConfig = lirePropriétés("app.properties")

// La clé de publication. Absente sur un poste qui ne publie pas : l'objet est alors vide.
val releaseKey = lirePropriétés("key.properties")

android {
    // Le namespace suit l'arborescence des sources Kotlin, pas l'identité publiée : il nomme
    // la classe R et résout les noms relatifs du manifeste (`.MainActivity`). Android n'exige
    // pas qu'il soit égal à l'applicationId, et c'est ce qui permet de trancher celui-ci sans
    // déplacer un seul fichier.
    namespace = "me.safe"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Écrit une seule fois, dans android/app.properties, que deploy/ lit aussi : l'APK
        // publié et la fiche du dépôt F-Droid ne peuvent pas annoncer deux identités
        // différentes. Ne se change plus après une première publication (SPEC §12.6).
        applicationId = appConfig.getProperty("applicationId")
            ?: error("applicationId manquant dans android/app.properties")
        // Android 8 en v0 (§7).
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Les bibliothèques natives suivent les plateformes que Flutter compile, et pas une de
        // plus. Sans ce filtre, MapLibre apportait son binaire x86_64 — 11 Mo — dans un APK
        // où ni le moteur Flutter ni l'app n'existaient pour cette architecture : du poids
        // mort qu'aucun appareil ne pouvait exécuter. La liste vient de `--target-platform`
        // (deploy/release-app.sh, TARGET_PLATFORMS) ; à défaut, les deux ARM d'Android.
        val plateformes = (project.findProperty("target-platform") as String?)
            ?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: listOf("android-arm", "android-arm64")
        ndk {
            abiFilters.clear()
            abiFilters.addAll(plateformes.map {
                when (it) {
                    "android-arm" -> "armeabi-v7a"
                    "android-arm64" -> "arm64-v8a"
                    "android-x64" -> "x86_64"
                    "android-x86" -> "x86"
                    else -> error("plateforme Flutter inconnue : $it")
                }
            })
        }
    }

    // La clé de publication vit hors du dépôt : `deploy/keystore.sh` la crée dans
    // ~/.app et écrit ici le fichier qui l'ouvre, jamais versionné. Android
    // identifie une application par le couple (applicationId, clé) — une mise à jour
    // signée autrement n'est pas une mise à jour, le système refuse de l'installer.
    signingConfigs {
        if (releaseKey.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sans `key.properties`, on retombe sur la signature de debug : un
            // `flutter build apk --release` reste utilisable sur un poste qui n'a pas la
            // clé. C'est `deploy/release-app.sh` qui refuse de publier ce qu'il obtient
            // alors — il compare l'empreinte du certificat à celle de vps.env.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")

            // R8 tourne sur ce type de build, et pas sur celui de debug : les règles
            // ci-dessous ne servent qu'à la publication, et leur absence ne se voyait pas
            // avant d'essayer. Voir proguard-rules.pro.
            proguardFiles("proguard-rules.pro")
        }
    }

    dependenciesInfo {
        // Ce bloc de métadonnées est chiffré par Google et illisible : un dépôt
        // F-Droid ne peut pas le reproduire, ce qui casse le build reproductible
        // exigé par le dépôt officiel (§12.6).
        includeInApk = false
        includeInBundle = false
    }
}

// Un plugin tire encore androidx.vectordrawable 1.0.0, dont le namespace entre en
// collision avec celui de vectordrawable-animated. Les versions 1.1.0 déclarent
// chacune le leur et le fusionneur de manifestes retombe sur ses pieds.
configurations.all {
    // Garde-fou de la contrainte F-Droid (§12.6) : aucune dépendance
    // propriétaire, y compris tirée transitivement par un futur plugin. Le build
    // casse plutôt que de laisser rentrer un blob sans qu'on s'en aperçoive.
    exclude(group = "com.google.android.gms")
    exclude(group = "com.google.firebase")

    resolutionStrategy {
        force("androidx.vectordrawable:vectordrawable:1.1.0")
        force("androidx.vectordrawable:vectordrawable-animated:1.1.0")
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
