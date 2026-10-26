# BlackHole — Android (native Kotlin + Vulkan)

An optimized native Android port of the Kerr black-hole simulation. It is **not**
a WebView wrapper — the renderer is real Vulkan running in the NDK, the physics
observables come from the same Rust `gravitas` engine the iOS/macOS apps use, and
the UI is Jetpack Compose.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Jetpack Compose UI  (MainActivity, ControlPanel, Hud)        │
│   · sliders / toggles / scenarios / quality presets          │
│   · drag → yaw·pitch, pinch → zoom (BlackHoleSurfaceView)    │
└───────────────┬──────────────────────────────┬──────────────┘
                │ JNI (NativeBridge)            │ JNI
                ▼                               ▼
┌──────────────────────────────┐   ┌──────────────────────────┐
│ Vulkan renderer (C++/NDK)    │   │ gravitas-ffi (Rust .a)    │
│  libblackhole.so             │   │  Kerr horizon / photon    │
│   1 scene  (raymarch frag)   │   │  sphere / ISCO / ergo     │
│   2 TAA    (history ping-pong)│  │  (statically linked in)   │
│   3 bright 4 blurH 5 blurV   │   └──────────────────────────┘
│   6 composite → swapchain    │
└──────────────────────────────┘
```

The renderer is a direct port of the macOS/iOS Metal pipeline
(`apple/BlackHole/Renderer/`):

- **Shaders** — `cpp/shaders/*.{vert,frag}` are GLSL ports of `BlackHole.metal`
  and `Postprocess.metal`. They compile to SPIR-V at build time with the NDK's
  `glslc` and are embedded into the binary as C arrays (no runtime asset I/O).
- **Feature flags** (lensing, disk, doppler, photon ring, stars, jets, redshift)
  map to **Vulkan specialization constants** — the exact analog of Metal function
  constants — so disabled effects fold out of the ray loop. Scene pipelines are
  cached per 7-bit flag mask.
- **Adaptive resolution** — a PID controller targets 60 FPS by scaling the
  offscreen render targets (ported 1:1 from `Renderer.swift`).
- **Camera smoothing + auto-spin** also ported from the Swift renderer.

## Build

Prerequisites (all already present on the dev machine that produced this):

- JDK 17, Android SDK (platform 35, build-tools 35), **NDK 27.2.12479018**,
  CMake 3.22.1
- Rust with the `aarch64-linux-android` and `x86_64-linux-android` targets
  (`rustup target add aarch64-linux-android x86_64-linux-android`)

`local.properties` must point at the SDK (`sdk.dir=...`). The Rust archive is
cross-compiled automatically by a Gradle task using the NDK toolchain — no
`cargo-ndk` or extra plugin required.

```bash
cd android
./gradlew :app:assembleDebug      # debug APK  → app/build/outputs/apk/debug/
./gradlew :app:bundleRelease      # Play .aab  → app/build/outputs/bundle/release/
```

ABIs shipped: `arm64-v8a` (devices) and `x86_64` (emulator). The App Bundle
splits by ABI/density/language so each device downloads only its slice.

## Signing & Play upload

1. Create an upload key (once):
   ```bash
   keytool -genkeypair -v -keystore upload-keystore.jks -alias upload \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Create `android/keystore.properties` (git-ignored):
   ```properties
   storeFile=upload-keystore.jks
   storePassword=********
   keyAlias=upload
   keyPassword=********
   ```
   If this file is absent the release bundle falls back to debug signing so the
   build still succeeds locally — but Play requires a real upload key.
3. `./gradlew :app:bundleRelease` → upload `app-release.aab` to the Play Console.
   Enrol in **Play App Signing** (recommended): your upload key signs the
   bundle, Google re-signs for distribution.

The release build enables R8 minification + resource shrinking and uploads full
native debug symbols (`debugSymbolLevel = "FULL"`) so Play can symbolicate native
crashes.

## Known caveats (no on-device GPU was available at port time)

- **Vertical orientation**: the post chain uses a consistent Vulkan
  framebuffer/sample convention; if the scene appears vertically mirrored vs the
  Metal build on a given device, flip the sign of `uv.y` in `blackhole.frag`'s
  camera setup (one line).
- **Surface rotation**: the swapchain uses `currentTransform` directly. On
  devices that report a non-identity transform in a given orientation the image
  may need pre-rotation handling; add a rotation matrix in the vertex shaders if
  you see this.
- **Single frame in flight**: the renderer waits on the previous frame's fence
  before reusing shared offscreen targets. The workload is GPU-bound so the cost
  is minimal; if you want more CPU/GPU overlap, duplicate the offscreen targets
  per in-flight frame.

These are localized, well-marked spots — none affect the build or packaging.
```
