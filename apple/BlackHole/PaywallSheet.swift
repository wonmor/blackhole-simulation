import SwiftUI
import StoreKit

/// Pro paywall. Built on StoreKit 2's `SubscriptionStoreView` so every
/// auto-renewable plan is listed with its App Store title, billing period
/// and localized price, with Terms of Use (Apple's standard EULA) and the
/// Privacy Policy linked right in the sheet (App Review Guideline 3.1.2).
///
/// Shown when the user opens a Pro feature (live wallpaper on macOS, the
/// Pomodoro timer) without an active subscription.
struct PaywallSheet: View {
    @ObservedObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            // Title, plan names/lengths and the policy links live OUTSIDE the
            // StoreKit view so they are readable even while products load
            // (or if the App Store cannot be reached).
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

            SubscriptionStoreView(productIDs: SubscriptionManager.productIDs) {
                marketingContent
            }
            .subscriptionStoreControlStyle(.prominentPicker)
            .subscriptionStoreButtonLabel(.multiline)
            .subscriptionStorePolicyDestination(url: AppLinks.termsOfUse, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: AppLinks.privacyPolicy, for: .privacyPolicy)
            .storeButton(.visible, for: .restorePurchases)
            .storeButton(.visible, for: .policies)
            .storeButton(.hidden, for: .cancellation)   // own close button in the header
            .onInAppPurchaseCompletion { product, result in
                await subscription.handlePurchaseResult(product, result)
                if subscription.isProUnlocked { dismiss() }
            }
            .tint(cyan)

            legal
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        #if os(macOS)
        .frame(width: 540, height: 680)
        #endif
        .background(Color.black.opacity(0.92))
        .colorScheme(.dark)
        .alert("StoreKit Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { subscription.lastError = nil }
        } message: {
            Text(subscription.lastError ?? "")
        }
    }

    // MARK: - Marketing content (scrolls above the plan picker)

    private var marketingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            features
            planSummary
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BlackHole Pro")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Auto-renewable subscription, monthly or yearly. The simulator, every slider, scenario, equation and quality preset stay free.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
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
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(macOS)
            Feature(icon: "rectangle.on.rectangle", text: "Live Kerr black hole as your desktop wallpaper (all displays, mouse parallax)")
            #endif
            Feature(icon: "timer", text: "Pomodoro focus timer over the simulation")
            Feature(icon: "arrow.triangle.2.circlepath", text: "One purchase unlocks Pro on iPhone, iPad and Mac")
        }
    }

    /// Plain-text listing of every plan: name, billing length and price, so
    /// the terms are readable even before the picker below finishes loading.
    private var planSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PLANS")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(cyan.opacity(0.85))
            if subscription.products.isEmpty {
                Text(subscription.isLoadingProducts
                     ? "Loading plans from the App Store…"
                     : "BlackHole Pro Monthly (billed every month) and BlackHole Pro Yearly (billed every year). Prices appear below once the App Store responds.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.60))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(subscription.products, id: \.id) { product in
                    HStack(alignment: .firstTextBaseline) {
                        Text(product.displayName.isEmpty ? fallbackName(product) : product.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.92))
                        Spacer(minLength: 8)
                        Text("\(product.displayPrice) / \(periodLabel(product))")
                            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Payment is charged to your Apple Account when you confirm the purchase. The subscription renews automatically at the same price and length unless it is cancelled at least 24 hours before the end of the current period. Manage or cancel it any time in your Apple Account subscription settings.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Link("Terms of Use (EULA)", destination: AppLinks.termsOfUse)
                Text("·").foregroundColor(.white.opacity(0.30))
                Link("Privacy Policy", destination: AppLinks.privacyPolicy)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(cyan)
        }
    }

    // MARK: - Helpers

    private func fallbackName(_ product: Product) -> String {
        product.id.contains("yearly") ? "BlackHole Pro Yearly" : "BlackHole Pro Monthly"
    }

    private func periodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "period" }
        let unit: String
        switch period.unit {
        case .day:   unit = "day"
        case .week:  unit = "week"
        case .month: unit = "month"
        case .year:  unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { subscription.lastError != nil },
            set: { _ in subscription.lastError = nil }
        )
    }
}

private struct Feature: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.55, green: 0.95, blue: 1.0))
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
