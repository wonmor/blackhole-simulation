import SwiftUI
import StoreKit

/// Sheet shown when the user tries to enable the live wallpaper without an
/// active Pro subscription. Lists available products, has Subscribe/Restore
/// buttons, and standard footer links.
struct PaywallSheet: View {
    @ObservedObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var purchasing: Bool = false
    @State private var selectedID: String?

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            features
            products
            Spacer(minLength: 4)
            footer
        }
        .padding(24)
        .frame(width: 460)
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
        .alert("StoreKit Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { subscription.lastError = nil }
        } message: {
            Text(subscription.lastError ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BlackHole Pro")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Live Kerr black hole on your desktop.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 8) {
            Feature(icon: "sparkles", text: "Live Kerr black hole as desktop wallpaper")
            Feature(icon: "square.grid.2x2", text: "Multi-display support")
            Feature(icon: "cursorarrow.motionlines", text: "Mouse-tracking parallax camera")
            Feature(icon: "speedometer", text: "Adaptive resolution + temporal AA")
        }
    }

    private var products: some View {
        VStack(spacing: 8) {
            if subscription.products.isEmpty {
                if subscription.isLoadingProducts {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    Text("Subscriptions are unavailable right now. Try again later.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            } else {
                ForEach(subscription.products, id: \.id) { product in
                    ProductRow(product: product,
                               isSelected: selectedID == product.id,
                               accent: cyan)
                        .onTapGesture { selectedID = product.id }
                }
            }
            Button {
                Task { await purchase() }
            } label: {
                HStack {
                    if purchasing { ProgressView().controlSize(.small) }
                    Text(purchaseLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(canPurchase ? cyan : Color.white.opacity(0.12))
                )
                .foregroundColor(canPurchase ? .black : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canPurchase || purchasing)
        }
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack {
            Button("Restore Purchase") {
                Task { await subscription.restore() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.65))

            Spacer()

            // Apple's standard EULA — the default Terms of Use for any app
            // that doesn't ship its own. Required for subscriptions per
            // App Review Guideline 3.1.2.
            Link("Terms of Use",
                 destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
            Text("·").foregroundColor(.white.opacity(0.30))
            Link("Privacy Policy",
                 destination: URL(string: "https://github.com/wonmor/blackhole-simulation/blob/main/PRIVACY.md")!)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: - Helpers

    private var canPurchase: Bool {
        guard let id = selectedID else { return false }
        return subscription.products.contains(where: { $0.id == id })
    }

    private var purchaseLabel: String {
        guard let id = selectedID,
              let p = subscription.products.first(where: { $0.id == id })
        else { return "Subscribe" }
        return "Subscribe — \(p.displayPrice)"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { subscription.lastError != nil },
            set: { _ in subscription.lastError = nil }
        )
    }

    private func purchase() async {
        guard let id = selectedID,
              let product = subscription.products.first(where: { $0.id == id })
        else { return }
        purchasing = true
        await subscription.purchase(product)
        purchasing = false
        if subscription.isProUnlocked { dismiss() }
    }
}

private struct Feature: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.55, green: 0.95, blue: 1.0))
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

private struct ProductRow: View {
    let product: Product
    let isSelected: Bool
    let accent: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName.isEmpty ? friendlyName : product.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(billingDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text(product.displayPrice)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? accent.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
    }

    private var friendlyName: String {
        product.id.contains("yearly") ? "Pro · Yearly" : "Pro · Monthly"
    }

    private var billingDescription: String {
        if let sub = product.subscription {
            let p = sub.subscriptionPeriod
            return "Renews every \(p.value) \(unitName(p.unit))"
        }
        return "Auto-renewing subscription"
    }

    private func unitName(_ u: Product.SubscriptionPeriod.Unit) -> String {
        switch u {
        case .day:   return "day"
        case .week:  return "week"
        case .month: return "month"
        case .year:  return "year"
        @unknown default: return "period"
        }
    }
}
