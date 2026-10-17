import SwiftUI

struct ContentView: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject var ui: UIState

    @State private var wallpaperToast: String? = nil

    #if os(macOS)
    @EnvironmentObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow
    #endif

    // Pinch-zoom state
    @State private var zoomBaseline: Float = 100.0
    @State private var pinching: Bool = false

    // Window focus — when the app loses focus, pause the simulation and
    // blur the rendered frame to save GPU. Refocusing resumes immediately.
    @Environment(\.scenePhase) private var scenePhase
    @State private var hostFocused: Bool = true

    /// Space reserved above the overlay. On macOS the window uses
    /// `.hiddenTitleBar`, so the traffic-light buttons sit on top of our
    /// content; keep the HUD clear of them.
    private var topInset: CGFloat {
        #if os(macOS)
        return 24
        #else
        return 0
        #endif
    }

    /// Height of the footer credit plus its padding — the panels may never
    /// grow into it.
    private let footerReserve: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            // Panels (HUD, control panel) scroll internally rather than
            // overflowing the window when it is short.
            let panelMaxHeight = max(220, geo.size.height - topInset - 32 - footerReserve)

            ZStack {
                MetalView(params: params, paused: !hostFocused)
                    .ignoresSafeArea()
                    // SwiftUI .blur on a Metal layer caches and re-blurs the
                    // rendered frame — on iOS, scenePhase transitions mid-frame
                    // (notification pull, control center) leave stale content
                    // visible. Restrict the blur effect to macOS where windowed
                    // focus changes are the only trigger.
                    #if os(macOS)
                    .blur(radius: hostFocused ? 0 : 18, opaque: true)
                    .animation(.easeInOut(duration: 0.18), value: hostFocused)
                    #endif
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
                    HStack(alignment: .top, spacing: 12) {
                        HUDView(params: params, showMath: $ui.showEquations)
                            .frame(maxHeight: panelMaxHeight, alignment: .top)
                        Spacer(minLength: 0)
                        controlsColumn(maxHeight: panelMaxHeight)
                    }
                    .padding(.top, topInset)
                    .padding(16)

                    Spacer(minLength: 0)

                    FooterView()
                        .padding(.bottom, 14)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(Color.black)
        .sheet(isPresented: $ui.showPomodoro) {
            PomodoroView(timer: pomodoro)
                .padding(.horizontal, 8)
        }
        // iPhone-only: ControlPanel as a bottom sheet (avoids width clipping).
        .sheet(isPresented: Binding(
            get: { ui.showControls && usesSheetForControls },
            set: { if !$0 { ui.showControls = false } }
        )) {
            ScrollView {
                controlPanelInstance
                    .padding(16)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $subscription.requestPaywall) {
            PaywallSheet(subscription: subscription)
        }
        .sheet(isPresented: $ui.showAbout) {
            AboutSheet()
                .padding(.horizontal, 8)
        }
        .sheet(isPresented: $ui.showWelcome, onDismiss: { ui.markWelcomeSeen() }) {
            WelcomeSheet(ui: ui)
                .padding(.horizontal, 8)
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
        .task {
            // Lets the menu bar / main menu re-open this window after the
            // user closed it (the app keeps running from the menu bar).
            controller.openMainWindow = { openWindow(id: "main") }
        }
        #endif
    }

    @ViewBuilder
    private func controlsColumn(maxHeight: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                #if os(macOS)
                if let toggle = liveWallpaperToggleAction {
                    homeIconButton(
                        symbol: liveWallpaperActive ? "stop.circle" : "rectangle.on.rectangle",
                        accent: liveWallpaperActive,
                        help: liveWallpaperActive ? "Stop Live Wallpaper" : "Set as Live Wallpaper"
                    ) {
                        if subscription.isProUnlocked || liveWallpaperActive {
                            toggle()
                        } else {
                            subscription.requestPaywall = true
                        }
                    }
                }
                #endif

                #if os(iOS)
                if let save = wallpaperSaveAction {
                    homeIconButton(symbol: "square.and.arrow.down", help: "Save as Wallpaper") {
                        save()
                    }
                }
                #endif

                homeIconButton(symbol: "timer", help: "Pomodoro") {
                    if subscription.isProUnlocked {
                        ui.showPomodoro = true
                    } else {
                        subscription.requestPaywall = true
                    }
                }

                homeIconButton(symbol: "slider.horizontal.3", accent: ui.showControls, help: "Controls") {
                    withAnimation(.easeInOut(duration: 0.15)) { ui.showControls.toggle() }
                }
            }

            // On iPhone (compact width), the side panel doesn't fit alongside
            // the HUD — present as a bottom sheet instead. iPad / Mac /
            // visionOS keep the inline side panel.
            if ui.showControls && !usesSheetForControls {
                controlPanelInstance
                    .frame(maxHeight: max(160, maxHeight - 44), alignment: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func homeIconButton(
        symbol: String,
        accent: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent ? Color(red: 0.55, green: 0.95, blue: 1.0).opacity(0.22)
                                     : Color.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            accent ? Color(red: 0.55, green: 0.95, blue: 1.0).opacity(0.55)
                                   : Color.white.opacity(0.10),
                            lineWidth: 0.7
                        )
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var controlPanelInstance: some View {
        ControlPanel(
            params: params,
            subscription: subscription,
            pomodoro: pomodoro,
            onPomodoroTap: { ui.showPomodoro = true },
            onWallpaperSaveTap: wallpaperSaveAction,
            onLiveWallpaperToggle: liveWallpaperToggleAction,
            liveWallpaperActive: liveWallpaperActive,
            onAboutTap: { ui.showAbout = true }
        )
    }

    private var usesSheetForControls: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
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

    private var liveWallpaperToggleAction: (() -> Void)? {
        #if os(macOS)
        return {
            controller.toggleMode(params: params, subscription: subscription)
        }
        #else
        return nil
        #endif
    }

    private var liveWallpaperActive: Bool {
        #if os(macOS)
        return controller.mode == .wallpaper
        #else
        return false
        #endif
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
        .lineLimit(1)
        .minimumScaleFactor(0.7)
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
