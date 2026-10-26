import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ---------------------------------------------------------------------------
// Signing — read from keystore.properties if present, otherwise fall back to
// the Android debug keystore so `bundleRelease` still produces an artifact for
// local testing. For Play upload, create android/keystore.properties (see
// android/RELEASE.md) pointing at a real upload key.
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Versioning — versionCode/versionName live in android/version.properties and
// are auto-incremented after every release bundle (see bumpVersionCode below),
// so each subsequent Play upload gets a strictly higher code automatically.
// ---------------------------------------------------------------------------
val versionPropsFile = rootProject.file("version.properties")
val versionProps = Properties().apply {
    if (versionPropsFile.exists()) load(FileInputStream(versionPropsFile))
}
val appVersionCode = (versionProps.getProperty("versionCode") ?: "1").toInt()
val appVersionName = versionProps.getProperty("versionName") ?: "1.0.0"

val keystorePropsFile = rootProject.file("keystore.properties")
val hasReleaseKeystore = keystorePropsFile.exists()
val keystoreProps = Properties().apply {
    if (hasReleaseKeystore) load(FileInputStream(keystorePropsFile))
}

android {
    namespace = "com.orchestrsim.blackhole"
    compileSdk = 36
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = "com.johnseong.blackhole"   // Google Play package id
        minSdk = 26                                       // Vulkan 1.1, rgba16f, AGSL-class GPUs
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersionName

        ndk {
            // Ship 64-bit only; Play requires arm64, x86_64 covers the emulator.
            abiFilters += listOf("arm64-v8a", "x86_64")
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    // Play requires 16 KB page-size support: align LOAD segments
                    // to 16 KB (NDK r27 flag; default in r28+).
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON",
                    // glslc ships inside the NDK; hand its path to CMake so the
                    // GLSL→SPIR-V step needs nothing on PATH.
                    "-DGLSLC_BIN=${glslcPath()}",
                    // Where the cargo task drops the cross-compiled Rust archives.
                    "-DRUST_LIBS_DIR=${rustLibsDir().absolutePath}"
                )
            }
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Debug-signed fallback so the .aab still builds locally.
                signingConfigs.getByName("debug")
            }
            ndk { debugSymbolLevel = "FULL" }   // upload native symbols to Play
        }
        debug {
            isJniDebuggable = true
            applicationIdSuffix = ".debug"
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // App Bundle: split by ABI / density / language so each device downloads
    // only the slice it needs.
    bundle {
        abi { enableSplit = true }
        density { enableSplit = true }
        language { enableSplit = true }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        // The Rust archive is statically linked into libblackhole.so; never ship it.
        jniLibs { useLegacyPackaging = false }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("com.android.billingclient:billing:8.3.0")

    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.compose.ui:ui-tooling-preview")
}

// ===========================================================================
// Auto-bump versionCode after each release bundle so the next upload is higher.
// The build above uses the *current* code; this finalizer increments the file
// for next time. Run `./gradlew bumpVersionCode` to bump manually.
// ===========================================================================
tasks.register("bumpVersionCode") {
    doLast {
        val f = rootProject.file("version.properties")
        val p = Properties().apply { if (f.exists()) load(FileInputStream(f)) }
        val cur = (p.getProperty("versionCode") ?: "1").toInt()
        val next = cur + 1
        p.setProperty("versionCode", next.toString())
        p.setProperty("versionName", p.getProperty("versionName") ?: appVersionName)
        f.outputStream().use { p.store(it, "BlackHole version — versionCode auto-incremented per release") }
        logger.lifecycle("versionCode bumped: $cur -> $next")
    }
}
// Lazily attach to bundleRelease (created by AGP) without forcing it to realize.
tasks.matching { it.name == "bundleRelease" }.configureEach { finalizedBy("bumpVersionCode") }

// ===========================================================================
// Rust → Android: cross-compile gravitas-ffi (staticlib) per ABI using the
// NDK clang toolchain, then stage the archive where CMake links it. No
// cargo-ndk or extra Gradle plugin required.
// ===========================================================================

fun glslcPath(): String {
    val host = "darwin-x86_64" // build host; NDK ships the macOS x86_64 binary (runs under Rosetta on arm Macs)
    return File(android.ndkDirectory, "shader-tools/$host/glslc").absolutePath
}

fun rustLibsDir(): File = layout.buildDirectory.dir("rustJniLibs").get().asFile

data class RustTarget(val abi: String, val triple: String, val api: Int)

val rustTargets = listOf(
    RustTarget("arm64-v8a", "aarch64-linux-android", 26),
    RustTarget("x86_64", "x86_64-linux-android", 26)
)

// Resolved relative to the project root (android/), so the default
// "../physics-engine" points at <repo>/physics-engine.
val rustWorkspace = rootProject.file(
    (project.findProperty("gravitas.workspace") as String? ?: "../physics-engine")
)

val cargoTasks = rustTargets.map { target ->
    tasks.register<Exec>("cargoBuild_${target.abi.replace("-", "_")}") {
        group = "rust"
        description = "Cross-compile gravitas-ffi for ${target.abi}"

        val ndkDir = android.ndkDirectory
        val toolchain = File(ndkDir, "toolchains/llvm/prebuilt/darwin-x86_64/bin")
        val linker = File(toolchain, "${target.triple}${target.api}-clang")
        val ar = File(toolchain, "llvm-ar")
        val outArchive = File(rustWorkspace, "target/${target.triple}/release/libgravitas_ffi.a")
        val staged = File(rustLibsDir(), "${target.abi}/libgravitas_ffi.a")

        // The Gradle daemon doesn't inherit the interactive shell PATH, so
        // resolve cargo (and its bin dir, for rustup) explicitly.
        val cargoHome = File(System.getProperty("user.home"), ".cargo/bin")
        val cargoBin = File(cargoHome, "cargo")
        val cargo = if (cargoBin.exists()) cargoBin.absolutePath else "cargo"

        workingDir = rustWorkspace
        commandLine(
            cargo, "build", "--release",
            "-p", "gravitas-ffi",
            "--target", target.triple
        )
        environment("PATH", "${cargoHome.absolutePath}:${System.getenv("PATH") ?: ""}")
        // staticlib needs no linker, but set it anyway so any future cdylib/build
        // scripts resolve the right cross toolchain.
        val tripleEnv = target.triple.uppercase().replace("-", "_")
        environment("CARGO_TARGET_${tripleEnv}_LINKER", linker.absolutePath)
        environment("CC_${target.triple}", linker.absolutePath)
        environment("AR_${target.triple}", ar.absolutePath)
        environment("CARGO_TERM_COLOR", "never")

        doLast {
            staged.parentFile.mkdirs()
            outArchive.copyTo(staged, overwrite = true)
            logger.lifecycle("Staged Rust archive: ${staged.absolutePath}")
        }
    }
}

// CMake (the externalNativeBuild tasks) must see the staged archives first.
tasks.configureEach {
    if (name.startsWith("configureCMake") || name.startsWith("buildCMake")) {
        dependsOn(cargoTasks)
    }
}
