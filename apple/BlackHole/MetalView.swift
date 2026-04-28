import SwiftUI
import MetalKit

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// SwiftUI wrapper for an MTKView driving the black-hole `Renderer`.
struct MetalView: PlatformViewRepresentable {
    @ObservedObject var params: BlackHoleParameters

    final class Coordinator {
        var renderer: Renderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeMTKView(coordinator: Coordinator) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not supported on this device.")
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        let renderer = Renderer(mtkView: view, params: params)
        coordinator.renderer = renderer
        view.delegate = renderer
        return view
    }

    private func updateMTKView(_ view: MTKView, coordinator: Coordinator) {
        // Push latest params into the renderer
        coordinator.renderer?.params = params
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView { makeMTKView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: MTKView, context: Context) { updateMTKView(nsView, coordinator: context.coordinator) }
    #else
    func makeUIView(context: Context) -> MTKView { makeMTKView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: MTKView, context: Context) { updateMTKView(uiView, coordinator: context.coordinator) }
    #endif
}
