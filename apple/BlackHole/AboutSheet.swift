import SwiftUI

/// "About BlackHole" sheet — version, credits, support links.
/// Cross-platform; same visual language as PaywallSheet / HUD.
struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                logo
                VStack(alignment: .leading, spacing: 3) {
                    Text("BLACKHOLE")
                        .font(.system(size: 18, weight: .ultraLight))
                        .tracking(5)
                        .foregroundColor(.white)
                    Text("Live Kerr black hole · iOS · macOS")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                closeButton
            }

            divider

            row(label: "VERSION", value: versionString)
            row(label: "RENDERER", value: "Metal 3 · MSL fragment shader")
            row(label: "PHYSICS", value: "Kerr-Schild geodesic · Page-Thorne disk")

            divider

            VStack(alignment: .leading, spacing: 6) {
                Text("CREDITS")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(cyan.opacity(0.85))
                Text("Developed by John Seong at Orch Aerospace, Inc.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Text("Fork of project by Mayank Pratap Singh")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }

            divider

            HStack(spacing: 10) {
                LinkPill(text: "Support",
                         url: URL(string: "https://github.com/wonmor/blackhole-simulation")!)
                LinkPill(text: "Privacy",
                         url: URL(string: "https://orchestrsim.com/privacy")!)
                LinkPill(text: "Terms",
                         url: URL(string: "https://orchestrsim.com/terms")!)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(panelBackground)
        .overlay(panelBorder)
        .colorScheme(.dark)
    }

    // MARK: - Bits

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
