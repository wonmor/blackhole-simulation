import SwiftUI

struct ContentView: View {
    @StateObject private var params = BlackHoleParameters()
    @State private var showControls: Bool = true

    // Pinch-zoom state
    @State private var zoomBaseline: Float = 30.0
    @State private var pinching: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MetalView(params: params)
                .ignoresSafeArea()
                .gesture(
                    SimultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let dx = Float(value.translation.width)
                                let dy = Float(value.translation.height)
                                params.yaw   = wrap01(params.yaw   + dx * 0.0008)
                                params.pitch = clamp(params.pitch + dy * 0.0012, lo: 0.05, hi: 0.95)
                            },
                        MagnificationGesture()
                            .onChanged { scale in
                                if !pinching { pinching = true; zoomBaseline = params.zoom }
                                let next = zoomBaseline / Float(max(0.1, scale))
                                params.zoom = clamp(next, lo: 1.5, hi: 100.0)
                            }
                            .onEnded { _ in
                                pinching = false
                            }
                    )
                )

            // FPS HUD (top-left)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.0f FPS", params.fps))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(fpsColor(params.fps))
                Text(params.preset.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, 16)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)

            // Control panel (top-right)
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showControls.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)

                if showControls {
                    ControlPanel(params: params)
                        .padding(.trailing, 16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(Color.black)
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps < 30 { return .red }
        if fps < 50 { return .yellow }
        return .white.opacity(0.9)
    }
}

private func clamp(_ x: Float, lo: Float, hi: Float) -> Float {
    return min(max(x, lo), hi)
}

private func wrap01(_ x: Float) -> Float {
    var v = x.truncatingRemainder(dividingBy: 1.0)
    if v < 0 { v += 1.0 }
    return v
}
