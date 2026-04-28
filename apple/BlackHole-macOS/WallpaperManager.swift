import AppKit
import Combine
import Metal
import MetalKit
import SwiftUI

/// Spawns one borderless click-through `NSWindow` per `NSScreen` at
/// `kCGDesktopIconWindowLevel - 1` so it sits between the static wallpaper
/// and the desktop icons. Each window hosts an `MTKView` + `Renderer` + a
/// SwiftUI overlay (countdown / expiry CTA).
///
/// Behaviors:
///   * Mouse-tracking parallax (cursor → small yaw/pitch offset)
///   * Pause on display sleep, resume on wake
///   * Pause when window is fully occluded by another app
///   * Preview countdown overlay during free trial
///   * Blur + center "Subscribe" CTA when preview expires; one click anywhere
///     on the wallpaper triggers `onExpiredClick` (typically: exit + paywall)
@MainActor
final class WallpaperManager: ObservableObject {

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPreviewExpired: Bool = false
    /// True while another app is the frontmost application. Causes wallpapers
    /// to apply a soft blur and pause the renderer (perf savings).
    @Published private(set) var isDimmed: Bool = false

    /// Set by `AppController` after binding subscription state. Invoked when
    /// the user clicks the expired wallpaper.
    var onExpiredClick: (() -> Void)?

    private var windows: [NSWindow] = []
    private var renderers: [Renderer] = []
    private var overlayHosts: [NSHostingView<WallpaperOverlay>] = []
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?
    private var occlusionObservers: [NSObjectProtocol] = []
    private var activeAppObserver: NSObjectProtocol?
    private var mouseMonitor: Any?

    /// Bundle IDs that DON'T trigger the dim state (the user is "looking at"
    /// the wallpaper when these are frontmost).
    private let homeBundleIDs: Set<String> = [
        Bundle.main.bundleIdentifier ?? "",
        "com.apple.finder",
    ]

    private weak var paramsRef: BlackHoleParameters?
    private weak var subscriptionRef: SubscriptionManager?

    private let yawRange: Float = 0.10
    private let pitchRange: Float = 0.05
    private let wallpaperFPS: Int = 30

    func start(params: BlackHoleParameters, subscription: SubscriptionManager) {
        guard !isRunning else { return }
        self.paramsRef = params
        self.subscriptionRef = subscription
        self.isPreviewExpired = false
        spawnWindows(params: params, subscription: subscription)
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
        overlayHosts.removeAll()
        isRunning = false
        isPreviewExpired = false
    }

    /// Called by AppController when the subscription preview expires.
    func markPreviewExpired() {
        isPreviewExpired = true
        for window in windows {
            // Capture clicks anywhere on the wallpaper now.
            window.ignoresMouseEvents = false
        }
        applyVisualState()
    }

    /// Recomputes blur + pause state from `isPreviewExpired` and `isDimmed`.
    /// Called whenever either input changes.
    private func applyVisualState() {
        let blurRadius: CGFloat = isPreviewExpired ? 18 : (isDimmed ? 12 : 0)
        let shouldPause = isPreviewExpired || isDimmed

        for window in windows {
            (window.contentView as? NSView)?.applyBlur(radius: blurRadius)
            if let mtk = window.contentView?.subviews.first(where: { $0 is MTKView }) as? MTKView {
                let occluded = !window.occlusionState.contains(.visible)
                mtk.isPaused = shouldPause || occluded
            }
        }
    }

    // MARK: - Windows

    private func spawnWindows(params: BlackHoleParameters, subscription: SubscriptionManager) {
        for screen in NSScreen.screens {
            spawnWindow(for: screen, params: params, subscription: subscription)
        }
    }

    private func spawnWindow(for screen: NSScreen,
                             params: BlackHoleParameters,
                             subscription: SubscriptionManager) {
        let frame = screen.frame
        let window = WallpaperWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

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
        window.onClick = { [weak self] in
            self?.onExpiredClick?()
        }

        // Container view: MTKView at the back, SwiftUI overlay on top.
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true

        let mtkView = MTKView(frame: container.bounds)
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = wallpaperFPS
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.autoresizingMask = [.width, .height]
        mtkView.wantsLayer = true

        let renderer = Renderer(mtkView: mtkView, params: params)
        mtkView.delegate = renderer
        container.addSubview(mtkView)

        let overlay = WallpaperOverlay(subscription: subscription)
        let host = NSHostingView(rootView: overlay)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.layer?.zPosition = 1
        container.addSubview(host)

        window.contentView = container
        window.orderFront(nil)

        windows.append(window)
        renderers.append(renderer)
        overlayHosts.append(host)
    }

    private func rebuildWindows() {
        guard let params = paramsRef, let subscription = subscriptionRef, isRunning else { return }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        renderers.removeAll()
        overlayHosts.removeAll()
        spawnWindows(params: params, subscription: subscription)
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

        // Pause individual wallpaper windows when fully occluded by another
        // app — saves significant GPU when the user is in a fullscreen app.
        for window in windows {
            let observer = center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.applyVisualState() }
            }
            occlusionObservers.append(observer)
        }

        // Dim + pause when another app becomes frontmost.
        activeAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                self.isDimmed = !self.homeBundleIDs.contains(bundleID ?? "")
                self.applyVisualState()
            }
        }
    }

    private func removeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        if let o = sleepObserver     { nc.removeObserver(o); sleepObserver = nil }
        if let o = wakeObserver      { nc.removeObserver(o); wakeObserver  = nil }
        if let o = activeAppObserver { nc.removeObserver(o); activeAppObserver = nil }
        if let o = screenChangeObserver {
            NotificationCenter.default.removeObserver(o); screenChangeObserver = nil
        }
        for o in occlusionObservers { NotificationCenter.default.removeObserver(o) }
        occlusionObservers.removeAll()
    }

    private func setPaused(_ paused: Bool) {
        for window in windows {
            (window.contentView?.subviews.first(where: { $0 is MTKView }) as? MTKView)?.isPaused = paused
        }
    }

    // MARK: - Mouse parallax

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.updateParallax() }
        }
    }

    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    private func updateParallax() {
        guard let params = paramsRef, !isPreviewExpired else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                 ?? NSScreen.main else { return }
        let frame = screen.frame
        let nx = Float((mouse.x - frame.midX) / max(frame.width, 1))
        let ny = Float((mouse.y - frame.midY) / max(frame.height, 1))

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

// MARK: - Custom NSWindow that forwards clicks

/// NSWindow subclass that forwards mouseDown to a closure. Used so that
/// once the preview expires we can detect the user clicking anywhere on
/// the wallpaper and exit to the paywall.
private final class WallpaperWindow: NSWindow {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onClick?()
        super.mouseDown(with: event)
    }
}

// MARK: - NSView blur helper

private extension NSView {
    func applyBlur(radius: CGFloat) {
        wantsLayer = true
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        layer?.backgroundFilters = [filter]
        layer?.masksToBounds = true
        // Re-display so the filter takes effect.
        layer?.setNeedsDisplay()
        layer?.displayIfNeeded()
    }
}
