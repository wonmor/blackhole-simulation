import SwiftUI
import StoreKit

/// BlackHole Pro paywall.
///
/// Lists all three ways to get Pro (monthly, yearly with a free trial when
/// the account is eligible, and a one-time lifetime unlock) with the App
/// Store's localized price and billing period on every option, a Restore
/// Purchases button, the auto-renewal terms, and links to the Terms of Use
/// (Apple's standard EULA) and the Privacy Policy (App Review Guideline
/// 3.1.2). Plan names, lengths and the legal links are visible even before
/// StoreKit responds.
struct PaywallSheet: View {
    @ObservedObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String = SubscriptionManager.yearlyID

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    features
                    plans
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            footer
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .background(Color.black.opacity(0.6))
        }
        #if os(macOS)
        .frame(width: 520, height: 720)
        #endif
        .background(Color.black.opacity(0.94))
        .colorScheme(.dark)
        .task {
            if subscription.products.isEmpty { await subscription.loadProducts() }
        }
        .onChange(of: subscription.isProUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        .onDisappear { subscription.paywallReason = nil }
        .alert("App Store", isPresented: errorBinding) {
            Button("OK", role: .cancel) { subscription.lastError = nil }
        } message: {
            Text(subscription.lastError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subscription.paywallReason.map { "\($0) is part of Pro" } ?? "BlackHole Pro")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The simulator, every slider, the Low to Ultra quality presets, four scenarios, two lessons and still-frame saving stay free. Pro adds the studio tools.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            Feature(icon: "camera.aperture", title: "Cinematic ray tracing",
                    text: "500 geodesic steps per pixel, twice Ultra: a sharper photon ring and more higher-order images.")
            #if os(iOS)
            Feature(icon: "photo", title: "4K poster export",
                    text: "Render a supersampled 4K still with 16-pass anti-aliasing and save it to Photos.")
            Feature(icon: "film", title: "Orbit video export",
                    text: "Render a smooth 12-second 360° fly-around as a 1080p video.")
            #endif
            Feature(icon: "sparkles", title: "Six more scenarios",
                    text: "M87*, an Interstellar-style disk, retrograde spin, Cygnus X-1, a quasar and a bare shadow.")
            Feature(icon: "graduationcap", title: "All eight lessons",
                    text: "Guided tours of Doppler beaming, redshift, frame dragging, the ISCO, disk colour and jets.")
            #if os(macOS)
            Feature(icon: "macwindow", title: "Live desktop wallpaper",
                    text: "The black hole renders behind your windows on every display.")
            #endif
            Feature(icon: "timer", title: "Focus timer",
                    text: "A Pomodoro timer over the simulation.")
            Feature(icon: "arrow.triangle.2.circlepath", title: "Every device",
                    text: "One purchase unlocks Pro on iPhone, iPad and Mac.")
        }
    }

    // MARK: - Plans

    private var plans: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHOOSE A PLAN")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(cyan.opacity(0.85))

            planRow(id: SubscriptionManager.yearlyID,
                    fallbackName: "BlackHole Pro Yearly",
                    fallbackTerms: "Billed every year, auto-renews")
            planRow(id: SubscriptionManager.monthlyID,
                    fallbackName: "BlackHole Pro Monthly",
                    fallbackTerms: "Billed every month, auto-renews")
            planRow(id: SubscriptionManager.lifetimeID,
                    fallbackName: "BlackHole Pro Lifetime",
                    fallbackTerms: "One-time purchase, no subscription")

            if subscription.products.isEmpty && !QAMock.enabled {
                HStack(spacing: 8) {
                    if subscription.isLoadingProducts {
                        ProgressView().controlSize(.small)
                        Text("Loading prices from the App Store…")
                    } else {
                        Text("Prices could not be loaded.")
                        Button("Try again") { Task { await subscription.loadProducts() } }
                            .foregroundColor(cyan)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func planRow(id: String, fallbackName: String, fallbackTerms: String) -> some View {
        let product = subscription.product(id)
        let selected = selectedID == id
        return Button { selectedID = id } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(cyan)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(planTitle(id))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        if let badge = badge(for: id) {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(cyan))
                        }
                    }
                    Text(product.map { terms(for: $0) } ?? QAMock.terms(id) ?? fallbackTerms)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product?.displayPrice ?? QAMock.price(id) ?? "")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                    Text(product.map { periodSuffix($0) } ?? QAMock.suffix(id) ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? cyan.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? cyan.opacity(0.7) : Color.white.opacity(0.12),
                                  lineWidth: selected ? 1.2 : 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(planTitle(id)), \(product?.displayPrice ?? "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Footer (CTA + legal)

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                guard let p = subscription.product(selectedID) else {
                    Task { await subscription.loadProducts() }
                    return
                }
                Task { await subscription.purchase(p) }
            } label: {
                HStack(spacing: 8) {
                    if subscription.isPurchasing { ProgressView().controlSize(.small).tint(.black) }
                    Text(ctaTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cyan))
            }
            .buttonStyle(.plain)
            .disabled(subscription.isPurchasing)
            .keyboardShortcut(.defaultAction)

            Text(ctaFinePrint)
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Subscriptions are charged to your Apple Account at confirmation of purchase (or when a free trial ends) and renew automatically at the same price and length unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your Apple Account settings. Lifetime is a single payment and does not renew.")
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Restore Purchases") { Task { await subscription.restore() } }
                    .disabled(subscription.isPurchasing)
                Text("|").foregroundColor(.white.opacity(0.25))
                Link("Terms of Use (EULA)", destination: AppLinks.termsOfUse)
                Text("|").foregroundColor(.white.opacity(0.25))
                Link("Privacy Policy", destination: AppLinks.privacyPolicy)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(cyan)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    // MARK: - Copy helpers

    private func planTitle(_ id: String) -> String {
        switch id {
        case SubscriptionManager.yearlyID:   return "Yearly"
        case SubscriptionManager.monthlyID:  return "Monthly"
        default:                             return "Lifetime"
        }
    }

    private func badge(for id: String) -> String? {
        if id == SubscriptionManager.yearlyID {
            if let save = yearlySavingsPercent { return "SAVE \(save)%" }
            return "BEST VALUE"
        }
        return nil
    }

    private var yearlySavingsPercent: Int? {
        guard let y = subscription.product(SubscriptionManager.yearlyID),
              let m = subscription.product(SubscriptionManager.monthlyID),
              m.price > 0 else { return nil }
        let ratio = (y.price as NSDecimalNumber).doubleValue / ((m.price as NSDecimalNumber).doubleValue * 12)
        let pct = Int(((1 - ratio) * 100).rounded())
        return pct >= 10 ? pct : nil
    }

    private func trialText(_ p: Product) -> String? {
        guard subscription.introEligible.contains(p.id),
              let offer = p.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return "\(periodText(offer.period, singular: true)) free"
    }

    private func terms(for p: Product) -> String {
        if p.type == .nonConsumable { return "One-time purchase. Pro forever, no subscription." }
        var parts: [String] = []
        if let t = trialText(p) {
            parts.append("\(t), then \(p.displayPrice) per \(periodText(p.subscription!.subscriptionPeriod, singular: false))")
        } else if let period = p.subscription?.subscriptionPeriod {
            parts.append("\(p.displayPrice) per \(periodText(period, singular: false)), auto-renews")
        }
        if p.id == SubscriptionManager.yearlyID {
            let perMonth = (p.price / 12).formatted(p.priceFormatStyle)
            parts.append("about \(perMonth) a month")
        }
        return parts.joined(separator: " | ")
    }

    private func periodSuffix(_ p: Product) -> String {
        guard let period = p.subscription?.subscriptionPeriod else { return "once" }
        return "per \(periodText(period, singular: false))"
    }

    /// (count, unit) with 7-day periods normalised to one week.
    private func unitParts(_ period: Product.SubscriptionPeriod) -> (Int, String) {
        switch period.unit {
        case .day:   return period.value % 7 == 0 ? (period.value / 7, "week") : (period.value, "day")
        case .week:  return (period.value, "week")
        case .month: return (period.value, "month")
        case .year:  return (period.value, "year")
        @unknown default: return (period.value, "period")
        }
    }

    /// "1 week" when `singular` (used for trial lengths), otherwise "week" /
    /// "3 months" (used after "per").
    private func periodText(_ period: Product.SubscriptionPeriod, singular: Bool) -> String {
        let (n, unit) = unitParts(period)
        if n == 1 { return singular ? "1 \(unit)" : unit }
        return "\(n) \(unit)s"
    }

    private var ctaTitle: String {
        guard let p = subscription.product(selectedID) else {
            if QAMock.enabled { return selectedID == SubscriptionManager.yearlyID ? "Start free trial" : "Continue" }
            return subscription.isLoadingProducts ? "Loading…" : "Continue"
        }
        if p.type == .nonConsumable { return "Unlock Pro for \(p.displayPrice)" }
        if trialText(p) != nil { return "Start free trial" }
        return "Subscribe for \(p.displayPrice)"
    }

    private var ctaFinePrint: String {
        guard let p = subscription.product(selectedID) else {
            if QAMock.enabled && selectedID == SubscriptionManager.yearlyID {
                return "1 week free. Then $29.99 per year until you cancel. Cancel any time before the trial ends and you won't be charged."
            }
            return "Choose Yearly, Monthly or Lifetime."
        }
        if p.type == .nonConsumable { return "Pay once. No renewals." }
        let period = periodText(p.subscription!.subscriptionPeriod, singular: false)
        if let t = trialText(p) {
            return "\(t.capitalizedFirst). Then \(p.displayPrice) per \(period) until you cancel. Cancel any time before the trial ends and you won't be charged."
        }
        return "\(p.displayPrice) per \(period) until you cancel."
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { subscription.lastError != nil },
            set: { _ in subscription.lastError = nil }
        )
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private struct Feature: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(red: 0.55, green: 0.95, blue: 1.0))
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Debug-only stand-in prices so simulator screenshots of the paywall show
/// real-looking plans when no StoreKit session is attached. Compiled out of
/// Release builds.
enum QAMock {
    static var enabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-bhMockPrices")
        #else
        return false
        #endif
    }
    static func price(_ id: String) -> String? {
        guard enabled else { return nil }
        switch id {
        case SubscriptionManager.yearlyID:  return "$29.99"
        case SubscriptionManager.monthlyID: return "$4.99"
        default:                            return "$49.99"
        }
    }
    static func suffix(_ id: String) -> String? {
        guard enabled else { return nil }
        switch id {
        case SubscriptionManager.yearlyID:  return "per year"
        case SubscriptionManager.monthlyID: return "per month"
        default:                            return "once"
        }
    }
    static func terms(_ id: String) -> String? {
        guard enabled else { return nil }
        switch id {
        case SubscriptionManager.yearlyID:  return "1 week free, then $29.99 per year | about $2.50 a month"
        case SubscriptionManager.monthlyID: return "1 week free, then $4.99 per month"
        default:                            return "One-time purchase. Pro forever, no subscription."
        }
    }
}
