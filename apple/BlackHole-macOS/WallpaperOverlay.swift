import SwiftUI

/// SwiftUI overlay shown on each wallpaper screen.
/// While preview is running: tiny "Trial · 1:30 left" pill, top-right.
/// When preview expires: large center CTA.
struct WallpaperOverlay: View {
    @ObservedObject var subscription: SubscriptionManager

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        ZStack {
            switch subscription.previewState {
            case .running:
                runningPill
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 24)
                    .padding(.trailing, 24)
                    .allowsHitTesting(false)

            case .expired:
                expiredCTA
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    // Don't intercept the click — wallpaper window itself catches
                    // it via WallpaperWindow.mouseDown so any click anywhere works.
                    .allowsHitTesting(false)

            case .available:
                EmptyView()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Running

    private var runningPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(cyan)
                .frame(width: 6, height: 6)
            Text("Trial · \(formatTime(subscription.previewSecondsRemaining)) left")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous).fill(Color.black.opacity(0.55))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    // MARK: - Expired

    private var expiredCTA: some View {
        VStack(spacing: 14) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(cyan)

            Text("Subscribe to BlackHole Pro")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Trial expired — click anywhere to continue.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white.opacity(0.65))

            HStack(spacing: 8) {
                Tag("Live wallpaper", icon: "sparkles")
                Tag("Multi-display",  icon: "square.grid.2x2")
                Tag("Mouse parallax", icon: "cursorarrow.motionlines")
            }
            .padding(.top, 6)
        }
        .padding(40)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.55), radius: 20, y: 6)
    }

    private struct Tag: View {
        let label: String
        let icon: String
        init(_ label: String, icon: String) { self.label = label; self.icon = icon }

        private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .tracking(0.4)
            }
            .foregroundColor(cyan)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous).fill(cyan.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(cyan.opacity(0.45), lineWidth: 0.6)
            )
        }
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let total = Int(ceil(s))
        let m = total / 60
        let sec = total % 60
        return String(format: "%d:%02d", m, sec)
    }
}
