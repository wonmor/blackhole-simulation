import Foundation
import StoreKit
#if os(visionOS) || os(iOS)
import UIKit
#endif

/// Bridges StoreKit 2 with the rest of the app.
///
/// In production the auto-renewing subscription product is registered in App
/// Store Connect with the IDs in `Self.productIDs` and StoreKit drives
/// `isProUnlocked`. For development (no App Store account / sandbox tester)
/// you can flip the `dev_pro_override` UserDefaults key — useful while we
/// build out the paywall and wallpaper flows before the live product exists.
@MainActor
final class SubscriptionManager: ObservableObject {

    /// Whether the user has an active Pro entitlement (any of the products).
    @Published private(set) var isProUnlocked: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published var lastError: String?
    /// Cross-platform signal for "show the paywall sheet now". Any caller
    /// (menu bar, ControlPanel, AppController) flips this true; the view
    /// tree presents `PaywallSheet` on its primary window.
    @Published var requestPaywall: Bool = false
    /// Which locked feature opened the paywall, shown as its headline.
    @Published var paywallReason: String?
    /// Overrides the paywall headline (the one-time post-"wow" prompt).
    @Published var paywallHeadline: String?
    /// True once StoreKit has answered the first entitlement check of the launch.
    @Published private(set) var entitlementsChecked: Bool = false

    /// Opens the paywall, optionally naming the feature the user tapped.
    func showPaywall(_ reason: String? = nil) {
        paywallReason = reason
        paywallHeadline = nil
        requestPaywall = true
    }

    // MARK: - Good moments (wow paywall + rating prompt)

    enum Moment { case scenario, lessonDone, snapshot }

    private let launchedAt = Date()

    /// A good moment just happened. Nothing fires on first touch: the one-time
    /// paywall waits for three such moments and 45 s with the simulator; the
    /// App Store rating prompt only follows a finished lesson or a saved
    /// snapshot, at most every 10 days (StoreKit adds its own limit).
    func noteMoment(_ m: Moment) {
        let d = UserDefaults.standard
        let count = d.integer(forKey: "bh.moments") + 1
        d.set(count, forKey: "bh.moments")
        if !isProUnlocked, !d.bool(forKey: "bh.wowShown"), count >= 3,
           Date().timeIntervalSince(launchedAt) >= 45 {
            d.set(true, forKey: "bh.wowShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, !self.isProUnlocked, !self.requestPaywall else { return }
                self.paywallReason = nil
                self.paywallHeadline = "Enjoying the view?"
                self.requestPaywall = true
            }
            return
        }
        guard m != .scenario else { return }
        let last = d.double(forKey: "bh.reviewAskedAt")
        let now = Date().timeIntervalSince1970
        guard now - last > 10 * 24 * 3600 else { return }
        d.set(now, forKey: "bh.reviewAskedAt")
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {
                AppStore.requestReview(in: scene)
            }
        }
        #endif
    }

    /// Hybrid free-trial: 90 seconds of live wallpaper per app launch.
    @Published private(set) var previewState: PreviewState = .available
    @Published private(set) var previewSecondsRemaining: TimeInterval = SubscriptionManager.previewTotalSeconds
    static let previewTotalSeconds: TimeInterval = 90.0
    private var previewTimer: Timer?

    enum PreviewState { case available, running, expired }

    /// Auto-renewing subscription product IDs. Platform-neutral (no `.ios` /
    /// `.mac` suffix) because we ship under Universal Purchase — a single App
    /// Store record covers iOS + iPadOS + macOS, and one purchase entitles the
    /// user across every platform.
    static let monthlyID  = "com.orchestrsim.blackholesim.pro_monthly"
    static let yearlyID   = "com.orchestrsim.blackholesim.pro_yearly"
    /// One-time, non-consumable purchase that unlocks Pro forever.
    static let lifetimeID = "com.orchestrsim.blackholesim.pro_lifetime"

    /// Auto-renewable subscriptions (the "BlackHole Pro" group).
    static let subscriptionIDs: [String] = [monthlyID, yearlyID]
    /// Every product that grants Pro.
    static let productIDs: [String] = [monthlyID, yearlyID, lifetimeID]

    /// Subscriptions whose introductory offer (free trial) this Apple Account
    /// is still eligible for.
    @Published private(set) var introEligible: Set<String> = []
    /// True while a purchase or restore is in flight (drives button spinners).
    @Published private(set) var isPurchasing: Bool = false
    /// Product id of the active entitlement, if any.
    @Published private(set) var activeProductID: String?

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    private static let devOverrideKey = "dev_pro_override"

    private var transactionListenerTask: Task<Void, Never>?

    init() {
        // Apply dev override immediately so debug builds light up the gated UI.
        let override = UserDefaults.standard.bool(forKey: Self.devOverrideKey)
        self.isProUnlocked = override

        transactionListenerTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update: update)
            }
        }

        Task {
            for await result in Transaction.unfinished {
                if case .verified(let t) = result { await t.finish() }
            }
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Public API

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            self.products = fetched.sorted { $0.price < $1.price }
            var eligible: Set<String> = []
            for p in fetched {
                if let sub = p.subscription, sub.introductoryOffer != nil,
                   await sub.isEligibleForIntroOffer {
                    eligible.insert(p.id)
                }
            }
            self.introEligible = eligible
        } catch {
            self.lastError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            #if os(visionOS)
            // visionOS requires a UIScene anchor for the purchase confirmation UI.
            guard let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
                    ?? (UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }.first) else {
                lastError = "No active window scene to host purchase."
                return
            }
            let result = try await product.purchase(confirmIn: scene)
            #else
            let result = try await product.purchase()
            #endif
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isProUnlocked {
                lastError = "No previous BlackHole Pro purchase was found for this Apple Account."
            }
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Debug-only toggle. Persists across launches via UserDefaults.
    func toggleDevOverride() {
        let cur = UserDefaults.standard.bool(forKey: Self.devOverrideKey)
        UserDefaults.standard.set(!cur, forKey: Self.devOverrideKey)
        Task { await refreshEntitlements() }
    }

    /// Re-reads current entitlements (used after StoreKit view purchases).
    func refresh() async {
        await refreshEntitlements()
    }

    /// Completion hook for `SubscriptionStoreView`'s `onInAppPurchaseCompletion`.
    func handlePurchaseResult(_ product: Product,
                              _ result: Result<Product.PurchaseResult, Error>) async {
        switch result {
        case .success(let purchase):
            switch purchase {
            case .success(let verification):
                do {
                    let transaction = try checkVerified(verification)
                    await transaction.finish()
                } catch {
                    lastError = error.localizedDescription
                }
                await refreshEntitlements()
            case .pending:
                lastError = "Purchase pending approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        case .failure(let error):
            lastError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Free-trial preview

    /// Starts the 90-second free preview. No-op if not in `.available` state.
    func startPreview() {
        guard previewState == .available else { return }
        previewState = .running
        previewSecondsRemaining = Self.previewTotalSeconds
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                self.previewSecondsRemaining = max(0, self.previewSecondsRemaining - 0.5)
                if self.previewSecondsRemaining <= 0 {
                    self.expirePreview()
                }
            }
        }
    }

    /// Marks the preview expired. Called on timer end or manual cancel.
    func expirePreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        if previewState == .running {
            previewState = .expired
        }
    }

    /// Convenience: a true running preview that hasn't expired.
    var isPreviewActive: Bool { previewState == .running }

    // MARK: - Internal

    private func refreshEntitlements() async {
        let override = UserDefaults.standard.bool(forKey: Self.devOverrideKey)
        var unlocked = override

        var active: String? = nil
        if !unlocked {
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result, Self.productIDs.contains(t.productID) {
                    if t.revocationDate != nil { continue }
                    if let exp = t.expirationDate, exp <= Date() { continue }
                    unlocked = true
                    // Prefer reporting the lifetime unlock if both exist.
                    if active == nil || t.productID == Self.lifetimeID { active = t.productID }
                }
            }
        }
        self.activeProductID = active
        self.isProUnlocked = unlocked
        self.entitlementsChecked = true
    }

    private func handle(update: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = update {
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let v): return v
        case .unverified: throw NSError(
            domain: "Subscription", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Transaction failed verification."]
        )
        }
    }
}
