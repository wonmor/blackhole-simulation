import SwiftUI

struct ContentView: View {
    @StateObject private var params = BlackHoleParameters()
    @State private var showControls: Bool = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MetalView(params: params)
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Map drag delta to yaw/pitch
                            let dx = Float(value.translation.width)
                            let dy = Float(value.translation.height)
                            params.yaw   = clamp(params.yaw   + dx * 0.0008, 0.0, 1.0, wrap: true)
                            params.pitch = clamp(params.pitch + dy * 0.0012, 0.05, 0.95)
                        }
                )

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showControls.toggle() }
                } label: {
                    Image(systemName: showControls ? "slider.horizontal.3" : "slider.horizontal.3")
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
}

private func clamp(_ x: Float, _ lo: Float, _ hi: Float, wrap: Bool = false) -> Float {
    if wrap {
        var v = x.truncatingRemainder(dividingBy: 1.0)
        if v < 0 { v += 1.0 }
        return v
    }
    return min(max(x, lo), hi)
}
