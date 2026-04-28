import Foundation
import StoreKit

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
    static let productIDs: [String] = [
        "com.orchestrsim.blackholesim.pro_monthly",
        "com.orchestrsim.blackholesim.pro_yearly",
    ]

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
        } catch {
            self.lastError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
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
        do {
            try await AppStore.sync()
            await refreshEntitlements()
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

        if !unlocked {
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result, Self.productIDs.contains(t.productID) {
                    if let exp = t.expirationDate, exp <= Date() { continue }
                    unlocked = true
                    break
                }
            }
        }
        self.isProUnlocked = unlocked
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
