import Foundation
import Combine

/// User-tunable simulation parameters. Mirrors a subset of the React `ControlPanel` schema.
final class BlackHoleParameters: ObservableObject {
    // Physics
    @Published var mass: Float = 1.0
    @Published var spin: Float = 0.7
    @Published var lensingStrength: Float = 1.0
    @Published var frameDragStrength: Float = 1.0

    // Disk
    @Published var diskDensity: Float = 1.0
    @Published var diskTemp: Float = 1.0           // multiplier on Novikov-Thorne base temp
    @Published var diskSize: Float = 8.0
    @Published var diskScaleHeight: Float = 0.08

    // Camera
    @Published var zoom: Float = 8.0
    @Published var yaw: Float = 0.5    // 0..1 mapped to 0..2π
    @Published var pitch: Float = 0.5  // 0..1 mapped to 0..π

    // Pipeline
    @Published var preset: QualityPreset = .high
    @Published var bloomThreshold: Float = 1.0
    @Published var bloomIntensity: Float = 0.45

    // Feature toggles
    @Published var enableLensing: Bool = true
    @Published var enableDisk: Bool = true
    @Published var enableStars: Bool = true
    @Published var enablePhotonGlow: Bool = true
    @Published var enableDoppler: Bool = true
    @Published var enableJets: Bool = false
    @Published var showRedshift: Bool = false
}
