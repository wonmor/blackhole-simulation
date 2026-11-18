import SwiftUI
import CompositorServices

@main
struct BlackHoleVisionApp: App {
    @StateObject private var params       = BlackHoleParameters()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var pomodoro     = PomodoroTimer()
    @ObservedObject private var control   = ImmersiveController.shared

    var body: some Scene {
        WindowGroup("iBlackHole", id: "control") {
            VisionControlsView(params: params, subscription: subscription, pomodoro: pomodoro)
                .sheet(isPresented: $subscription.requestPaywall) {
                    PaywallSheet(subscription: subscription)
                }
        }
        .defaultSize(width: 760, height: 900)

        // The black hole itself: ray traced per eye with Metal through
        // CompositorServices. Mixed immersion keeps the room visible around it;
        // full immersion surrounds you with the lensed starfield.
        ImmersiveSpace(id: "blackhole-immersive") {
            CompositorLayer(configuration: ImmersiveLayerConfig()) { layerRenderer in
                let renderer = ImmersiveRenderer(layerRenderer: layerRenderer, params: params)
                renderer.startRenderLoop()
            }
        }
        .immersionStyle(selection: styleBinding, in: .mixed, .full)
        .upperLimbVisibility(.visible)
    }

    private var styleBinding: Binding<any ImmersionStyle> {
        Binding(
            get: { control.mode == .space ? (FullImmersionStyle.full as any ImmersionStyle) : (MixedImmersionStyle.mixed as any ImmersionStyle) },
            set: { _ in }
        )
    }
}

/// Dedicated layout: one texture per eye, rendered in its own pass (works on
/// the simulator, which has no vertex amplification, and on device).
/// Foveation on so the composite pass shades the periphery at a lower rate.
private struct ImmersiveLayerConfig: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                           configuration: inout LayerRenderer.Configuration) {
        let foveation = capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveation
        let layouts = capabilities.supportedLayouts(options: foveation ? [.foveationEnabled] : [])
        configuration.layout = layouts.contains(.dedicated) ? .dedicated : (layouts.first ?? .dedicated)
    }
}
