import SwiftUI
import CompositorServices

@main
struct BlackHoleVisionApp: App {
    @StateObject private var params       = BlackHoleParameters()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var pomodoro     = PomodoroTimer()

    @State private var immersionStyle: ImmersionStyle = .full

    var body: some Scene {
        // Floating control window — slim variant of ControlPanel without
        // the live MetalView preview (rendering happens in the immersive
        // space instead).
        WindowGroup("BlackHole", id: "control") {
            VisionControlsView(params: params,
                               subscription: subscription,
                               pomodoro: pomodoro)
                .preferredColorScheme(.dark)
                .frame(minWidth: 480, idealWidth: 540, minHeight: 700)
                .sheet(isPresented: $subscription.requestPaywall) {
                    PaywallSheet(subscription: subscription)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 820)

        // The actual simulation — fully immersive, surrounding the user.
        ImmersiveSpace(id: "blackhole-immersive") {
            CompositorLayer(configuration: ImmersiveLayerConfig()) { layerRenderer in
                let renderer = ImmersiveRenderer(layerRenderer: layerRenderer,
                                                 params: params)
                renderer.startRenderLoop()
            }
        }
        .immersionStyle(selection: $immersionStyle, in: .full)
    }
}

/// Minimal CompositorLayer config for full immersion.
///
/// `layout = .dedicated` forces separate per-eye textures so we can render
/// each eye in its own pass without vertex amplification — works on both
/// the visionOS simulator (no amplification support) and real device.
/// We let Compositor pick the color / depth formats so the pipeline
/// descriptor we build later matches what the drawable actually provides.
private struct ImmersiveLayerConfig: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        configuration.isFoveationEnabled = capabilities.supportsFoveation
        configuration.layout = .dedicated
    }
}
