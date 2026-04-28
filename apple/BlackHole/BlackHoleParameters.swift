import Foundation
import Combine

/// User-tunable simulation parameters. Mirrors a subset of the React `ControlPanel` schema.
final class BlackHoleParameters: ObservableObject {
    // Physics
    @Published var mass: Float = 1.0
    @Published var spin: Float = 0.5
    @Published var lensingStrength: Float = 1.0

    // Disk
    @Published var diskDensity: Float = 1.0
    @Published var diskTemp: Float = 1.0
    @Published var diskSize: Float = 6.0

    // Camera
    @Published var zoom: Float = 8.0
    @Published var yaw: Float = 0.5    // 0..1 mapped to 0..2π
    @Published var pitch: Float = 0.5  // 0..1 mapped to 0..π

    // Quality / debug
    @Published var maxRaySteps: Int = 200
    @Published var debug: Bool = false
    @Published var showRedshift: Bool = false
}
