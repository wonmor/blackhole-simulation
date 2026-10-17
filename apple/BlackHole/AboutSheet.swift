import SwiftUI

/// "About BlackHole" sheet — what the app computes, version, credits,
/// support and policy links. Cross-platform; same visual language as the
/// paywall and HUD.
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        #if os(macOS)
        content
            .frame(width: 480)
        #else
        ScrollView {
            content
        }
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                logo
                VStack(alignment: .leading, spacing: 3) {
                    Text("BLACKHOLE")
                        .font(.system(size: 18, weight: .ultraLight))
                        .tracking(5)
                        .foregroundColor(.white)
                    Text("Real-time Kerr black hole simulator")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                closeButton
            }

            divider

            sectionTitle("WHAT IT COMPUTES")
            Text("BlackHole integrates null geodesics through the Kerr–Schild metric in a Metal fragment shader, so every pixel of every frame is a light ray traced through the curved spacetime of a rotating black hole on your GPU. Nothing is pre-rendered: change the mass or spin and the shadow, gravitational lensing, frame-dragging and the Page–Thorne accretion disk (Doppler boost, Novikov–Thorne temperature profile, blackbody colour) are recomputed live.")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                point("Live readouts of the event horizon, photon sphere and ISCO radii for the current mass and spin (Bardeen 1973; Bardeen, Press & Teukolsky 1972).")
                point("An equations panel (EQS in the HUD) listing each closed-form expression the renderer evaluates, with its citation.")
                point("Scenarios: stellar-mass, Sgr A* proxy, near-extremal Kerr and non-rotating Schwarzschild.")
                point("Quality presets that trade ray-marching steps, render scale, temporal AA and bloom for frame rate.")
            }

            divider

            row(label: "VERSION", value: versionString)
            row(label: "RENDERER", value: "Metal 3 · MSL fragment shader")
            row(label: "PHYSICS", value: "Kerr-Schild geodesic · Page-Thorne disk")

            divider

            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("CREDITS")
                Text("Developed by John Seong at Orch Aerospace, Inc.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Text("Fork of project by Mayank Pratap Singh (MIT License)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }

            divider

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    LinkPill(text: "Support", url: AppLinks.support)
                    LinkPill(text: "Physics notes", url: AppLinks.physicsNotes)
                    Spacer()
                }
                HStack(spacing: 10) {
                    LinkPill(text: "Privacy Policy", url: AppLinks.privacyPolicy)
                    LinkPill(text: "Terms of Use", url: AppLinks.termsOfUse)
                    Spacer()
                }
                Text("Terms of Use are Apple's standard End User License Agreement.")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.40))
            }
        }
        .padding(24)
        .background(panelBackground)
        .overlay(panelBorder)
        .colorScheme(.dark)
    }

    // MARK: - Bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .tracking(1.4)
            .foregroundColor(cyan.opacity(0.85))
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(cyan.opacity(0.8)).frame(width: 4, height: 4).padding(.top, 5)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logo: some View {
        ZStack {
            Circle()
                .strokeBorder(cyan.opacity(0.55), lineWidth: 1)
                .frame(width: 42, height: 42)
            Circle()
                .fill(.black)
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(.white, lineWidth: 0.6)
                .frame(width: 30, height: 30)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .padding(6)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .keyboardShortcut(.cancelAction)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.50))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.trailing)
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.30))
        }
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.8
            )
    }
}

private struct LinkPill: View {
    let text: String
    let url: URL
    var body: some View {
        Link(destination: url) {
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
        }
    }
}
