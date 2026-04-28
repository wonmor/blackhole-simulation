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
        VStack(spacing: 22) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundColor(cyan.opacity(0.85))

            VStack(spacing: 14) {
                Text("SUBSCRIBE TO BLACKHOLE PRO")
                    .font(.system(size: 30, weight: .ultraLight))
                    .tracking(7)
                    .foregroundColor(.white.opacity(0.95))

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 64, height: 1)

                VStack(spacing: 4) {
                    Text("TRIAL EXPIRED")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(3.5)
                        .foregroundColor(cyan.opacity(0.85))
                    Text("Click anywhere to continue")
                        .font(.system(size: 12, weight: .light))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            HStack(spacing: 10) {
                Tag("LIVE WALLPAPER", icon: "sparkles")
                Tag("MULTI-DISPLAY",  icon: "square.grid.2x2")
                Tag("MOUSE PARALLAX", icon: "cursorarrow.motionlines")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 44)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .light))
                Text(label)
                    .font(.system(size: 9, weight: .light))
                    .tracking(2.0)
            }
            .foregroundColor(cyan.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(cyan.opacity(0.30), lineWidth: 0.6)
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
