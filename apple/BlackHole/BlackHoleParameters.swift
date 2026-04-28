import Foundation
import Combine

/// User-tunable simulation parameters.
/// Defaults and ranges mirror `src/configs/simulation.config.ts` from the web.
///
/// All persistable fields are written to `UserDefaults` on `didSet` and read
/// back on init, so the app remembers the user's settings across launches.
final class BlackHoleParameters: ObservableObject {

    // MARK: - Geometry
    @Published var mass: Float = 1.0                       { didSet { persist("mass", mass) } }
    @Published var spin: Float = 0.5                       { didSet { persist("spin", spin) } }
    @Published var lensingStrength: Float = 0.7            { didSet { persist("lens", lensingStrength) } }
    @Published var frameDragStrength: Float = 2.0          { didSet { persist("frameDrag", frameDragStrength) } }

    // MARK: - Disk
    @Published var diskDensity: Float = 4.0                { didSet { persist("diskDensity", diskDensity) } }
    @Published var diskTemp: Float = 9500.0                { didSet { persist("diskTemp", diskTemp) } }
    @Published var diskSize: Float = 50.0                  { didSet { persist("diskSize", diskSize) } }
    @Published var diskScaleHeight: Float = 0.2            { didSet { persist("diskScale", diskScaleHeight) } }

    // MARK: - Camera
    @Published var zoom: Float = 100.0                     { didSet { persist("zoom", zoom) } }
    @Published var yaw: Float = 0.5                        { didSet { persist("yaw", yaw) } }
    @Published var pitch: Float = 0.539                    { didSet { persist("pitch", pitch) } }
    @Published var autoSpin: Float = 0.005                 { didSet { persist("autoSpin", autoSpin) } }

    // MARK: - Pipeline
    @Published var preset: QualityPreset = .high           { didSet { persist("preset", preset.rawValue) } }
    @Published var bloomThreshold: Float = 1.0             { didSet { persist("bloomThr", bloomThreshold) } }
    @Published var bloomIntensity: Float = 0.45            { didSet { persist("bloomInt", bloomIntensity) } }

    // MARK: - Feature toggles (default to web `high-quality` preset)
    @Published var enableLensing: Bool = true              { didSet { persist("enLens", enableLensing) } }
    @Published var enableDisk: Bool = true                 { didSet { persist("enDisk", enableDisk) } }
    @Published var enableStars: Bool = true                { didSet { persist("enStars", enableStars) } }
    @Published var enablePhotonGlow: Bool = true           { didSet { persist("enPhoton", enablePhotonGlow) } }
    @Published var enableDoppler: Bool = true              { didSet { persist("enDoppler", enableDoppler) } }
    @Published var enableJets: Bool = true                 { didSet { persist("enJets", enableJets) } }
    @Published var showRedshift: Bool = false              { didSet { persist("showRedshift", showRedshift) } }

    // MARK: - Telemetry (NOT persisted — transient render state)
    @Published var fps: Double = 0
    @Published var frameTimeMs: Double = 0
    @Published var effectiveRenderScale: Float = 1.0

    /// Wall-clock time of the most recent user interaction. Renderer pauses
    /// auto-spin briefly so the camera doesn't fight the user.
    var lastInteraction: TimeInterval = 0

    // MARK: - Init / persistence

    /// Set true while loading from UserDefaults so didSet writes don't loop.
    private var loading: Bool = false

    init() {
        load()
    }

    private static let prefix = "bh.params."

    private func persist<T>(_ key: String, _ value: T) {
        guard !loading else { return }
        UserDefaults.standard.set(value, forKey: Self.prefix + key)
    }

    private func load() {
        loading = true
        defer { loading = false }
        let d = UserDefaults.standard
        if let v = d.object(forKey: Self.prefix + "mass")        as? Float { mass = v }
        if let v = d.object(forKey: Self.prefix + "spin")        as? Float { spin = v }
        if let v = d.object(forKey: Self.prefix + "lens")        as? Float { lensingStrength = v }
        if let v = d.object(forKey: Self.prefix + "frameDrag")   as? Float { frameDragStrength = v }
        if let v = d.object(forKey: Self.prefix + "diskDensity") as? Float { diskDensity = v }
        if let v = d.object(forKey: Self.prefix + "diskTemp")    as? Float { diskTemp = v }
        if let v = d.object(forKey: Self.prefix + "diskSize")    as? Float { diskSize = v }
        if let v = d.object(forKey: Self.prefix + "diskScale")   as? Float { diskScaleHeight = v }
        if let v = d.object(forKey: Self.prefix + "zoom")        as? Float { zoom = v }
        if let v = d.object(forKey: Self.prefix + "yaw")         as? Float { yaw = v }
        if let v = d.object(forKey: Self.prefix + "pitch")       as? Float { pitch = v }
        if let v = d.object(forKey: Self.prefix + "autoSpin")    as? Float { autoSpin = v }
        if let raw = d.string(forKey: Self.prefix + "preset"),
           let p = QualityPreset(rawValue: raw) { preset = p }
        if let v = d.object(forKey: Self.prefix + "bloomThr")    as? Float { bloomThreshold = v }
        if let v = d.object(forKey: Self.prefix + "bloomInt")    as? Float { bloomIntensity = v }
        if let v = d.object(forKey: Self.prefix + "enLens")      as? Bool  { enableLensing = v }
        if let v = d.object(forKey: Self.prefix + "enDisk")      as? Bool  { enableDisk = v }
        if let v = d.object(forKey: Self.prefix + "enStars")     as? Bool  { enableStars = v }
        if let v = d.object(forKey: Self.prefix + "enPhoton")    as? Bool  { enablePhotonGlow = v }
        if let v = d.object(forKey: Self.prefix + "enDoppler")   as? Bool  { enableDoppler = v }
        if let v = d.object(forKey: Self.prefix + "enJets")      as? Bool  { enableJets = v }
        if let v = d.object(forKey: Self.prefix + "showRedshift") as? Bool { showRedshift = v }
    }
}
