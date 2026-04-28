import Foundation
import Combine

/// User-tunable simulation parameters.
/// Defaults and ranges mirror `src/configs/simulation.config.ts` from the web build.
final class BlackHoleParameters: ObservableObject {
    // Geometry
    @Published var mass: Float = 1.0
    @Published var spin: Float = 0.5
    @Published var lensingStrength: Float = 0.7
    /// `gravity.frameDraggingStrength` from the web physics config.
    @Published var frameDragStrength: Float = 2.0

    // Disk (temperatures are raw Kelvin, density is web's "rel" units)
    @Published var diskDensity: Float = 4.0
    @Published var diskTemp: Float = 9500.0
    @Published var diskSize: Float = 50.0
    @Published var diskScaleHeight: Float = 0.2

    // Camera
    @Published var zoom: Float = 30.0
    @Published var yaw: Float = 0.5    // 0..1 mapped to 0..2π
    @Published var pitch: Float = 0.5  // 0..1 mapped to 0..π
    /// Continuous yaw drift in rad/s. Web default 0.005 rad/s ("Cam Auto-Pan").
    @Published var autoSpin: Float = 0.005

    // Pipeline
    @Published var preset: QualityPreset = .high
    @Published var bloomThreshold: Float = 1.0
    @Published var bloomIntensity: Float = 0.45

    // Feature toggles (defaults match web `high-quality` preset)
    @Published var enableLensing: Bool = true
    @Published var enableDisk: Bool = true
    @Published var enableStars: Bool = true
    @Published var enablePhotonGlow: Bool = true
    @Published var enableDoppler: Bool = true
    @Published var enableJets: Bool = true
    @Published var showRedshift: Bool = false

    // Telemetry
    @Published var fps: Double = 0
}
