import SwiftUI

struct ContentView: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var pomodoro: PomodoroTimer

    @State private var showControls: Bool = false
    @State private var showPomodoro: Bool = false
    @State private var wallpaperToast: String? = nil

    // Pinch-zoom state
    @State private var zoomBaseline: Float = 100.0
    @State private var pinching: Bool = false

    // Window focus — when the app loses focus, pause the simulation and
    // blur the rendered frame to save GPU. Refocusing resumes immediately.
    @Environment(\.scenePhase) private var scenePhase
    @State private var hostFocused: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                MetalView(params: params, paused: !hostFocused)
                    .ignoresSafeArea()
                    .blur(radius: hostFocused ? 0 : 18, opaque: true)
                    .animation(.easeInOut(duration: 0.18), value: hostFocused)
                    .gesture(
                        SimultaneousGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let s = Float(min(geo.size.width, geo.size.height))
                                    let dx = Float(value.translation.width)  / max(s, 1)
                                    let dy = Float(value.translation.height) / max(s, 1)
                                    params.yaw   = wrap01(params.yaw   + dx * 1.0)
                                    params.pitch = clamp(params.pitch + dy * 0.9, lo: 0.05, hi: 0.95)
                                    params.lastInteraction = CFAbsoluteTimeGetCurrent()
                                },
                            MagnificationGesture()
                                .onChanged { scale in
                                    if !pinching { pinching = true; zoomBaseline = params.zoom }
                                    let next = zoomBaseline / Float(max(0.1, scale))
                                    params.zoom = clamp(next, lo: 1.5, hi: 100.0)
                                    params.lastInteraction = CFAbsoluteTimeGetCurrent()
                                }
                                .onEnded { _ in
                                    pinching = false
                                }
                        )
                    )

                // Foreground UI layer
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        HUDView(params: params)
                        Spacer(minLength: 0)
                        controlsColumn
                    }
                    .padding(16)

                    Spacer(minLength: 0)

                    FooterView()
                        .padding(.bottom, 14)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(Color.black)
        .sheet(isPresented: $showPomodoro) {
            PomodoroView(timer: pomodoro)
                .padding(.horizontal, 8)
        }
        .sheet(isPresented: $subscription.requestPaywall) {
            PaywallSheet(subscription: subscription)
        }
        .alert("Wallpaper", isPresented: wallpaperToastBinding, actions: {
            Button("OK", role: .cancel) { wallpaperToast = nil }
        }, message: {
            Text(wallpaperToast ?? "")
        })
        .onChange(of: scenePhase) { _, phase in
            hostFocused = (phase == .active)
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            hostFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hostFocused = true
        }
        #endif
    }

    @ViewBuilder
    private var controlsColumn: some View {
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

            if showControls {
                ControlPanel(
                    params: params,
                    subscription: subscription,
                    pomodoro: pomodoro,
                    onPomodoroTap: { showPomodoro = true },
                    onWallpaperSaveTap: wallpaperSaveAction
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    // MARK: - Helpers

    private var wallpaperSaveAction: (() -> Void)? {
        #if os(iOS)
        return {
            Task {
                await WallpaperSaver.shared.capture()
                switch WallpaperSaver.shared.status {
                case .saved:
                    wallpaperToast = "Saved to Photos. Open Photos → tap → Share → Use as Wallpaper."
                case .denied:
                    wallpaperToast = "Photos access denied. Enable it in Settings → BlackHole."
                case .failed(let m):
                    wallpaperToast = "Couldn't save: \(m)"
                default:
                    break
                }
                WallpaperSaver.shared.reset()
            }
        }
        #else
        return nil
        #endif
    }

    private var wallpaperToastBinding: Binding<Bool> {
        Binding(get: { wallpaperToast != nil },
                set: { if !$0 { wallpaperToast = nil } })
    }
}

/// Bottom-of-screen credit. Two lines, tight tracking, low opacity so it never
/// fights with the simulation behind it.
private struct FooterView: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("DEVELOPED BY JOHN SEONG AT ORCH AEROSPACE, INC.")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(2.0)
                .foregroundColor(.white.opacity(0.55))
            Text("Fork of project by Mayank Pratap Singh")
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.30))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
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
