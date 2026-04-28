# BlackHole — iOS & macOS

Native iOS / macOS Metal port of the WebGPU/WebGL black-hole simulation.

## v1 status

- Metal raymarching shader ported from `src/shaders/blackhole/raymarching.wgsl.ts`
- SwiftUI app shells for iOS 17+ and macOS 14+
- Shared Renderer + ControlPanel + uniforms layout
- Drag-to-rotate camera
- Sliders: mass, spin, lensing, disk size/density/temp, zoom, ray steps
- Newtonian-corrected gravity (not yet full Kerr geodesics — see "Roadmap")

The Rust `gravitas-core` engine is **not yet wired in**. v1 does its geodesic
integration on the GPU, so the app stands up without the Rust core. A build
script for the eventual xcframework lives at `scripts/build-gravitas-xcframework.sh`.

## Build (one-time setup)

```bash
brew install xcodegen     # if you don't have it (you already do)
cd apple
xcodegen generate         # produces BlackHole.xcodeproj
open BlackHole.xcodeproj  # or `xcodebuild …` from CLI
```

## Build from CLI

```bash
# macOS app
xcodebuild -project apple/BlackHole.xcodeproj \
           -scheme BlackHole-macOS \
           -configuration Debug \
           -destination 'platform=macOS' \
           build

# iOS Simulator
xcodebuild -project apple/BlackHole.xcodeproj \
           -scheme BlackHole-iOS \
           -configuration Debug \
           -destination 'generic/platform=iOS Simulator' \
           build
```

To run on a real iOS device, set `DEVELOPMENT_TEAM` in `project.yml` to your
Apple Developer Team ID, regenerate, and build with a connected device.

## Layout

```
apple/
├── project.yml                       # XcodeGen spec
├── BlackHole/                        # Shared sources (both targets)
│   ├── BlackHoleParameters.swift
│   ├── ContentView.swift
│   ├── ControlPanel.swift
│   ├── MetalView.swift
│   ├── Renderer/
│   │   ├── Renderer.swift
│   │   └── Shaders.metal
│   └── Shared/
│       ├── ShaderTypes.h             # Shared between Swift and MSL
│       └── BlackHole-Bridging-Header.h
├── BlackHole-iOS/
│   ├── Info.plist
│   └── iOSApp.swift
├── BlackHole-macOS/
│   ├── Info.plist
│   └── macOSApp.swift
└── scripts/
    └── build-gravitas-xcframework.sh
```

## Roadmap (post-v1)

1. **Full Kerr geodesics in MSL** — port `src/shaders/blackhole/chunks/metric.ts`
   (Kerr horizon / photon sphere / ISCO / `kerr_geodesic_accel`) to Metal.
2. **ATAA** — port `src/shaders/postprocess/ataa.wgsl` for temporal AA.
3. **Bloom + ACES tone mapping** — port from `src/shaders/postprocess/`.
4. **Wire in `gravitas-core`** — author `physics-engine/gravitas-ffi`, expose
   extern "C" surface (camera ray builder, shadow curve generator, ISCO/photon
   sphere computations), build via `scripts/build-gravitas-xcframework.sh`,
   call from Swift to fill diagnostic overlays and high-precision quantities.
5. **Quality presets + cinematic camera paths** — mirror the React side.
6. **iPad pencil / trackpad gestures** for camera control.
