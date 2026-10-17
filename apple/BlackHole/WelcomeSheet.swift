import SwiftUI

/// First-launch explainer. Shown once (see `UIState.showWelcome`) and again
/// from Help ▸ "What is BlackHole?" on macOS. Spells out what the app
/// actually computes so the purpose is obvious before the first drag.
struct WelcomeSheet: View {
    @ObservedObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        #if os(macOS)
        content.frame(width: 480)
        #else
        ScrollView { content }
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                logo
                VStack(alignment: .leading, spacing: 4) {
                    Text("BLACKHOLE")
                        .font(.system(size: 20, weight: .ultraLight))
                        .tracking(5)
                        .foregroundColor(.white)
                    Text("A real-time general-relativity simulator, not a video loop.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Text("Every frame traces light rays backwards through the curved spacetime of a spinning (Kerr) black hole on your GPU. Change the mass or spin and the shadow, lensing, and accretion disk are re-solved from the metric, live.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                bullet("slider.horizontal.3", "Tune the physics",
                       "Mass, spin a*, lensing, frame-dragging, disk size, density, temperature and scale height. The HUD reports the event horizon, photon sphere and ISCO radii as you drag.")
                bullet("function", "See the equations",
                       "Tap EQS in the HUD to list every closed-form equation the shader evaluates, with its literature citation (Bardeen, Page–Thorne, Novikov–Thorne).")
                bullet("star.fill", "Load a scenario",
                       "One tap jumps to a stellar-mass hole, a Sgr A* proxy, a near-extremal Kerr hole, or a non-rotating Schwarzschild hole.")
                bullet("hand.draw", "Explore",
                       "Drag to orbit, pinch or scroll to zoom from the photon ring out past the disk.")
            }

            HStack(spacing: 10) {
                Button {
                    ui.markWelcomeSeen()
                    ui.showAbout = true
                } label: {
                    Text("Learn more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    ui.markWelcomeSeen()
                    dismiss()
                } label: {
                    Text("Start exploring")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(cyan))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.30))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
        )
        .colorScheme(.dark)
    }

    private func bullet(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(cyan)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var logo: some View {
        ZStack {
            Circle().strokeBorder(cyan.opacity(0.55), lineWidth: 1).frame(width: 42, height: 42)
            Circle().fill(.black).frame(width: 22, height: 22)
            Circle().strokeBorder(.white, lineWidth: 0.6).frame(width: 30, height: 30)
        }
    }
}
