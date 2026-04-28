import SwiftUI
import MetalKit

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

#if os(macOS)
/// MTKView subclass that forwards scroll-wheel events as zoom deltas.
final class ScrollableMTKView: MTKView {
    var onScrollDelta: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        // Trackpad two-finger scroll uses scrollingDeltaY; mouse uses deltaY.
        let dy = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        onScrollDelta?(dy)
    }
    override var acceptsFirstResponder: Bool { true }
}
#endif

struct MetalView: PlatformViewRepresentable {
    @ObservedObject var params: BlackHoleParameters
    /// When true, the renderer's MTKView is paused — saves GPU when the
    /// host window loses focus or the app is backgrounded.
    var paused: Bool = false

    final class Coordinator {
        var renderer: Renderer?
        weak var view: MTKView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func configure(view: MTKView, coordinator: Coordinator) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported on this device.")
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        // Framebuffer-only false on iOS so WallpaperSaver can blit from the
        // drawable texture into a staging texture for Photos export.
        #if os(iOS)
        view.framebufferOnly = false
        #else
        view.framebufferOnly = true
        #endif
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        let renderer = Renderer(mtkView: view, params: params)
        coordinator.renderer = renderer
        coordinator.view = view
        view.delegate = renderer

        #if os(iOS)
        WallpaperSaver.shared.mtkView = view
        #endif
    }

    private func updateMTKView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.renderer?.params = params
        view.isPaused = paused
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView {
        let view = ScrollableMTKView()
        configure(view: view, coordinator: context.coordinator)
        view.onScrollDelta = { [weak params] dy in
            guard let params = params else { return }
            // Negative dy = scroll up = zoom in.
            let next = params.zoom * Float(1.0 - dy * 0.01)
            params.zoom = min(max(next, 1.5), 100.0)
            params.lastInteraction = CFAbsoluteTimeGetCurrent()
        }
        return view
    }
    func updateNSView(_ nsView: MTKView, context: Context) {
        updateMTKView(nsView, coordinator: context.coordinator)
    }
    #else
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        configure(view: view, coordinator: context.coordinator)
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {
        updateMTKView(uiView, coordinator: context.coordinator)
    }
    #endif
}
