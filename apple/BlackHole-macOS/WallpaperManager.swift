import AppKit
import Combine
import Metal
import MetalKit

/// Spawns one borderless, click-through `NSWindow` per `NSScreen` at
/// `kCGDesktopIconWindowLevel - 1` so it sits between the static wallpaper and
/// the desktop icons. Each window hosts its own `MTKView` + `Renderer` and
/// shares the global `BlackHoleParameters` instance.
///
/// Also installs a global mouse-move monitor while running, mapping cursor
/// position on the active screen to a small yaw / pitch offset for parallax.
@MainActor
final class WallpaperManager: ObservableObject {

    @Published private(set) var isRunning: Bool = false

    private var windows: [NSWindow] = []
    private var renderers: [Renderer] = []
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?
    private var mouseMonitor: Any?

    private weak var paramsRef: BlackHoleParameters?

    /// Mouse-driven parallax range. ±yawRange yaw units, ±pitchRange pitch.
    private let yawRange: Float = 0.10
    private let pitchRange: Float = 0.05

    /// Frame rate cap for wallpaper rendering — 30 FPS keeps the GPU cool
    /// when the simulation is running 24/7 on the desktop.
    private let wallpaperFPS: Int = 30

    func start(params: BlackHoleParameters) {
        guard !isRunning else { return }
        self.paramsRef = params
        spawnWindows(params: params)
        installObservers()
        installMouseMonitor()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        removeMouseMonitor()
        removeObservers()
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        renderers.removeAll()
        isRunning = false
    }

    // MARK: - Windows

    private func spawnWindows(params: BlackHoleParameters) {
        for screen in NSScreen.screens {
            spawnWindow(for: screen, params: params)
        }
    }

    private func spawnWindow(for screen: NSScreen, params: BlackHoleParameters) {
        let frame = screen.frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        // Sit between desktop wallpaper and desktop icons.
        let level = Int(CGWindowLevelForKey(.desktopIconWindow)) - 1
        window.level = NSWindow.Level(rawValue: level)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.title = "BlackHole Wallpaper"
        window.titleVisibility = .hidden

        let mtkView = MTKView(frame: NSRect(origin: .zero, size: frame.size))
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = wallpaperFPS
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.autoresizingMask = [.width, .height]

        let renderer = Renderer(mtkView: mtkView, params: params)
        mtkView.delegate = renderer

        window.contentView = mtkView
        window.orderFront(nil)

        windows.append(window)
        renderers.append(renderer)
    }

    private func rebuildWindows() {
        guard let params = paramsRef, isRunning else { return }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        renderers.removeAll()
        spawnWindows(params: params)
    }

    // MARK: - Observers

    private func installObservers() {
        let center = NotificationCenter.default
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setPaused(true) }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setPaused(false) }
        }
        screenChangeObserver = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindows() }
        }
    }

    private func removeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        if let o = sleepObserver { nc.removeObserver(o); sleepObserver = nil }
        if let o = wakeObserver  { nc.removeObserver(o); wakeObserver  = nil }
        if let o = screenChangeObserver {
            NotificationCenter.default.removeObserver(o)
            screenChangeObserver = nil
        }
    }

    private func setPaused(_ paused: Bool) {
        for window in windows {
            (window.contentView as? MTKView)?.isPaused = paused
        }
    }

    // MARK: - Mouse parallax

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateParallax()
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func updateParallax() {
        guard let params = paramsRef else { return }
        let mouse = NSEvent.mouseLocation
        // Find the screen the cursor is currently on so multi-display works.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                 ?? NSScreen.main else { return }
        let frame = screen.frame
        let nx = Float((mouse.x - frame.midX) / max(frame.width, 1))   // -0.5..0.5
        let ny = Float((mouse.y - frame.midY) / max(frame.height, 1))  // -0.5..0.5

        let baseYaw: Float = 0.5
        let basePitch: Float = 0.539

        var yaw = baseYaw + nx * yawRange * 2.0
        yaw = yaw.truncatingRemainder(dividingBy: 1.0)
        if yaw < 0 { yaw += 1.0 }

        let pitch = max(0.05, min(0.95, basePitch - ny * pitchRange * 2.0))

        params.yaw = yaw
        params.pitch = pitch
        params.lastInteraction = CFAbsoluteTimeGetCurrent()
    }
}
