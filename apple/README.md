# BlackHole — iOS & macOS

Native iOS / macOS Metal port of the WebGPU/WebGL black-hole simulation.

## Status

- Full Kerr geodesic raymarcher in MSL (Kerr-Schild Hamiltonian + Bardeen
  effective potential + ZAMO frame-dragging) — ported from
  `src/shaders/blackhole/chunks/metric.ts`.
- Page–Thorne accretion disk with exact Doppler factor + Tanner-Helland
  blackbody — ported from `src/shaders/blackhole/chunks/disk.ts` and
  `chunks/blackbody.ts`.
- Spectral starfield + nebula — ported from `chunks/background.ts`.
- Optional relativistic jets aligned with the spin axis.
- Multipass HDR pipeline: `scene → TAA → bright → blur H/V → composite`.
- ACES tone mapping + gamma 2.2 in the composite pass (ported from
  `chunks/common.ts` and `postprocess/bloom.glsl.ts`).
- Neighborhood-clamped temporal AA in YCoCg space (ported from
  `postprocess/ataa.wgsl.ts`); history reset on large camera motion.
- Quality presets (Low / Medium / High / Ultra) tune ray steps, render
  scale, TAA, and bloom independently.
- Drag-to-rotate, pinch-zoom (iOS + Mac trackpad), and scroll-wheel zoom
  on macOS.
- `gravitas-ffi` crate authored at `physics-engine/gravitas-ffi/` exposing
  the C-ABI surface (Kerr horizon, photon sphere, ISCO, ergosphere,
  analytic shadow curve). Swift wrapper at `BlackHole/Bridge/Gravitas.swift`
  with pure-Swift fallbacks for the no-toolchain case.

## Build

```bash
cd apple
xcodegen generate
open BlackHole.xcodeproj
```

For CLI builds (no IDE):

```bash
xcodebuild -project apple/BlackHole.xcodeproj \
           -scheme BlackHole-macOS \
           -configuration Debug -destination 'platform=macOS' build

xcodebuild -project apple/BlackHole.xcodeproj \
           -scheme BlackHole-iOS \
           -configuration Debug \
           -destination 'generic/platform=iOS Simulator' build
```

To run on a real iPhone, set `DEVELOPMENT_TEAM` in `project.yml` to your
Apple Developer Team ID and re-run `xcodegen generate`.

## Wiring the Rust kernel (optional)

The Metal scene shader does its own geodesic integration on-GPU, so the
app runs today without Rust. To swap the Swift Bardeen formulas in
`Bridge/Gravitas.swift` for the validated `gravitas-core` Rust kernel:

1. Install `rustup` (https://rustup.rs).
2. Build the xcframework:
   ```bash
   cd apple
   ./scripts/build-gravitas-xcframework.sh
   ```
   This produces `apple/build/Gravitas.xcframework`.
3. Add the framework to `project.yml` under both targets:
   ```yaml
   dependencies:
     - framework: build/Gravitas.xcframework
       embed: false
   ```
4. Add `GRAVITAS_LINKED` to each target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
   so the bridge in `Bridge/Gravitas.swift` switches to the C symbols.
5. Re-run `xcodegen generate`.

## Layout

```
apple/
├── project.yml                       # XcodeGen spec
├── BlackHole/                        # Shared sources (both targets)
│   ├── BlackHoleParameters.swift     # ObservableObject for sliders + toggles
│   ├── ContentView.swift             # Drag + pinch gestures + control toggle
│   ├── ControlPanel.swift            # Sliders, preset picker, toggles
│   ├── MetalView.swift               # Cross-platform MTKView wrapper
│   ├── QualityPreset.swift           # Low / Med / High / Ultra
│   ├── Bridge/
│   │   └── Gravitas.swift            # Swift ↔ gravitas-ffi shim
│   ├── Renderer/
│   │   ├── Renderer.swift            # Multipass pipeline driver
│   │   ├── BlackHole.metal           # Kerr scene fragment shader (HDR out)
│   │   └── Postprocess.metal         # TAA + bloom + composite
│   └── Shared/
│       ├── ShaderTypes.h             # Shared C struct (Swift + MSL)
│       └── BlackHole-Bridging-Header.h
├── BlackHole-iOS/
│   ├── Info.plist
│   └── iOSApp.swift
├── BlackHole-macOS/
│   ├── Info.plist
│   └── macOSApp.swift
└── scripts/
    └── build-gravitas-xcframework.sh # Rust → fat xcframework
```

## Quality presets

| Preset | Ray steps | Render scale | TAA | Bloom |
|--------|-----------|--------------|-----|-------|
| Low    | 80        | 0.6×         | off | off   |
| Medium | 160       | 0.8×         | on  | on    |
| High   | 240       | 1.0×         | on  | on    |
| Ultra  | 360       | 1.0×         | on  | on    |

## Roadmap

- **Spectrum LUT for blackbody** — sample the validated LUT from the React
  pipeline instead of the analytic Tanner-Helland approximation, for
  better near-horizon redshift fidelity.
- **Kerr shadow overlay** — wire `Gravitas.shadowCurve` into a Metal
  texture and overlay the analytic critical curve as a diagnostic.
- **HDR EDR output** on supported macOS / iOS displays (extended dynamic
  range; needs `extendedRange16Float` colorspace).
- **Cinematic camera paths** — port the React cinematic system.
