import Foundation

/// Visual-quality budget for the render pipeline. Higher presets cost more GPU.
enum QualityPreset: String, CaseIterable, Identifiable {
    case low, medium, high, ultra

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .ultra:  return "Ultra"
        }
    }

    var maxRaySteps: Int {
        switch self {
        case .low:    return 80
        case .medium: return 160
        case .high:   return 240
        case .ultra:  return 360
        }
    }

    var renderScale: Float {
        switch self {
        case .low:    return 0.6
        case .medium: return 0.8
        case .high:   return 1.0
        case .ultra:  return 1.0
        }
    }

    var taaEnabled: Bool {
        switch self {
        case .low:    return false
        case .medium: return true
        case .high:   return true
        case .ultra:  return true
        }
    }

    var bloomEnabled: Bool {
        switch self {
        case .low:    return false
        case .medium: return true
        case .high:   return true
        case .ultra:  return true
        }
    }
}
