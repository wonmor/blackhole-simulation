import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Visual-quality budget for the render pipeline. Higher presets cost more GPU.
/// Step counts match `SIMULATION_CONFIG.rayTracingSteps` from the web build.
enum QualityPreset: String, CaseIterable, Identifiable {
    case low, medium, high, ultra
    /// Pro: the shader's maximum ray budget (500 geodesic steps, ~2x Ultra)
    /// with TAA + bloom. Sharper photon ring and higher-order lensed images.
    case cinematic

    /// Best default for the current device. Errs on the conservative side —
    /// users can always crank up via the Quality picker.
    ///
    ///   * iOS Simulator       → low   (renders on Mac CPU, very slow)
    ///   * visionOS            → low   (stereo at 4K per eye is brutal)
    ///   * iPhone (any A-chip) → medium
    ///   * iPad                → high
    ///   * macOS Apple Silicon → ultra
    ///   * macOS Intel         → high
    static var autoDetected: QualityPreset {
        #if targetEnvironment(simulator)
        return .low
        #elseif os(visionOS)
        return .medium
        #elseif os(macOS)
        #if arch(arm64)
        return .ultra
        #else
        return .high
        #endif
        #else
        // iOS / iPadOS — pick by idiom if we're on iPad, otherwise iPhone.
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? .high : .medium
        #else
        return .medium
        #endif
        #endif
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .ultra:  return "Ultra"
        case .cinematic: return "Cinematic"
        }
    }

    /// Short label for the compact segmented picker.
    var shortName: String {
        switch self {
        case .medium: return "Med"
        case .cinematic: return "Cine"
        default: return displayName
        }
    }

    /// Cinematic is the only Pro preset; Low to Ultra stay free.
    var isPro: Bool { self == .cinematic }

    /// Mirrors the web `rayTracingSteps` table: 32 / 64 / 128 / 256.
    var maxRaySteps: Int {
        switch self {
        case .low:    return 32
        case .medium: return 64
        case .high:   return 128
        case .ultra:  return 256
        case .cinematic: return 500   // shader clamps to 500
        }
    }

    var renderScale: Float {
        switch self {
        case .low:    return 0.5
        case .medium: return 0.75
        case .high:   return 1.0
        case .ultra:  return 1.0
        case .cinematic: return 1.0
        }
    }

    var taaEnabled: Bool {
        switch self {
        case .low:    return false
        case .medium: return true
        case .high:   return true
        case .ultra:  return true
        case .cinematic: return true
        }
    }

    var bloomEnabled: Bool {
        switch self {
        case .low:    return false
        case .medium: return false
        case .high:   return true
        case .ultra:  return true
        case .cinematic: return true
        }
    }
}
