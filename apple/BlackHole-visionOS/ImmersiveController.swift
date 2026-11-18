import Foundation
import SwiftUI
import simd

/// Which kind of immersive space is showing.
enum SpaceMode: String {
    case room   // mixed immersion: the black hole floats in your room
    case space  // full immersion: lensed starfield all around
}

/// State shared between the window (main thread) and the Compositor render
/// thread. Values the renderer reads every frame live behind a lock; the
/// window observes the published copies.
final class ImmersiveController: ObservableObject, @unchecked Sendable {
    static let shared = ImmersiveController()

    // Published for the window.
    @Published var isOpen = false
    @Published var mode: SpaceMode = .room
    @Published var fps: Double = 0
    @Published var renderScale: Float = 0.7

    private let lock = NSLock()

    // Interaction state (lock protected).
    private var _yaw: Float = 0.35          // orbit around the spin axis
    private var _tilt: Float = 0.0          // extra tilt added by pinch-drag
    private var _size: Float = 1.0          // magnify gesture / size slider
    private var _recenter = true
    private var _renderMode: SpaceMode = .room

    struct Snapshot {
        var yaw: Float
        var tilt: Float
        var size: Float
        var recenter: Bool
        var mode: SpaceMode
    }

    /// Renderer reads (and consumes the recenter flag) once per frame.
    func takeSnapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let s = Snapshot(yaw: _yaw, tilt: _tilt, size: _size, recenter: _recenter, mode: _renderMode)
        _recenter = false
        return s
    }

    var size: Float {
        get { lock.lock(); defer { lock.unlock() }; return _size }
        set { lock.lock(); _size = min(max(newValue, 0.35), 3.0); lock.unlock() }
    }

    func orbit(dYaw: Float, dTilt: Float) {
        lock.lock()
        _yaw += dYaw
        _tilt = min(max(_tilt + dTilt, -1.3), 1.3)
        lock.unlock()
    }

    func resetOrientation() {
        lock.lock(); _yaw = 0.35; _tilt = 0; lock.unlock()
    }

    func requestRecenter() {
        lock.lock(); _recenter = true; lock.unlock()
    }

    func setMode(_ m: SpaceMode) {
        lock.lock(); _renderMode = m; lock.unlock()
        if Thread.isMainThread { mode = m } else { DispatchQueue.main.async { self.mode = m } }
    }

    func publish(fps: Double, scale: Float) {
        DispatchQueue.main.async {
            self.fps = fps
            self.renderScale = scale
        }
    }

    func setOpen(_ open: Bool) {
        DispatchQueue.main.async { self.isOpen = open }
    }
}
