import SwiftUI

/// Control window shown beside the immersive space on visionOS.
/// Reuses the existing `ControlPanel` (sliders, scenarios, paywall trigger,
/// pomodoro launcher) and adds an "Enter / Exit Immersive" button.
struct VisionControlsView: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var pomodoro: PomodoroTimer

    @Environment(\.openImmersiveSpace)  private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var inImmersive: Bool = false
    @State private var showPomodoro: Bool = false
    @State private var showAbout: Bool = false

    var body: some View {
        VStack(spacing: 22) {
            header

            Button {
                Task {
                    if inImmersive {
                        await dismissImmersiveSpace()
                        inImmersive = false
                    } else {
                        if !subscription.isProUnlocked {
                            // Free preview of immersive on visionOS too.
                            switch subscription.previewState {
                            case .available: subscription.startPreview()
                            case .running:   break
                            case .expired:
                                subscription.requestPaywall = true
                                return
                            }
                        }
                        let result = await openImmersiveSpace(id: "blackhole-immersive")
                        if case .opened = result { inImmersive = true }
                    }
                }
            } label: {
                Text(inImmersive ? "EXIT IMMERSIVE" : "ENTER IMMERSIVE")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(2.0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.55, green: 0.95, blue: 1.0))

            ControlPanel(
                params: params,
                subscription: subscription,
                pomodoro: pomodoro,
                onPomodoroTap: { showPomodoro = true },
                onAboutTap:    { showAbout = true }
            )
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(20)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPomodoro)  { PomodoroView(timer: pomodoro) }
        .sheet(isPresented: $showAbout)     { AboutSheet() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.dotted.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(red: 0.55, green: 0.95, blue: 1.0))
            Text("BLACKHOLE")
                .font(.system(size: 14, weight: .ultraLight))
                .tracking(4)
                .foregroundColor(.white.opacity(0.95))
            Spacer()
        }
    }
}
