package com.orchestrsim.blackhole.billing

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams

/**
 * Google Play Billing for BlackHole Pro.
 *
 * Products (Play Console):
 *  - one-time product `blackhole_pro_lifetime` (the main offer);
 *  - subscription `blackhole_pro`, base plan `yearly` (P1Y) with a 1-week
 *    free-trial offer. The legacy `monthly` base plan stays active for
 *    existing subscribers but is no longer shown on the paywall.
 *
 * Any active purchase of either unlocks Pro. The last known entitlement is
 * cached so Pro works offline; Play remains the source of truth and is
 * re-queried on every launch and resume.
 */
class ProManager(private val context: Context) : PurchasesUpdatedListener {

    companion object {
        const val SUB_ID = "blackhole_pro"
        const val LIFETIME_ID = "blackhole_pro_lifetime"
        const val PLAN_MONTHLY = "monthly"
        const val PLAN_YEARLY = "yearly"
        private const val PREF_KEY = "pro_cached"
        private const val PREF_HAD_SUB = "had_sub"
        /** Cross-process Pro flag read by the live wallpaper (separate process). */
        const val PRO_FLAG_FILE = "pro.flag"

        fun proFlag(context: Context): Boolean =
            java.io.File(context.filesDir, PRO_FLAG_FILE).exists()
    }

    private val prefs = context.getSharedPreferences("bh.billing", Context.MODE_PRIVATE)

    var isPro by mutableStateOf(prefs.getBoolean(PREF_KEY, false)); private set
    var subDetails by mutableStateOf<ProductDetails?>(null); private set
    var lifetimeDetails by mutableStateOf<ProductDetails?>(null); private set
    var loading by mutableStateOf(true); private set
    var busy by mutableStateOf(false); private set
    var message by mutableStateOf<String?>(null)

    /** Paywall presentation + which locked feature opened it. */
    var showPaywall by mutableStateOf(false)
    var paywallReason by mutableStateOf<String?>(null)
    /** Overrides the paywall headline (used by the post-"wow" prompt). */
    var paywallHeadline by mutableStateOf<String?>(null)

    fun openPaywall(reason: String? = null) {
        paywallReason = reason
        paywallHeadline = null
        showPaywall = true
    }

    /** Soft prompt shown once, after the user has enjoyed the free simulator. */
    fun openPaywallAfterWow() {
        paywallReason = null
        paywallHeadline = "Enjoying the view?"
        showPaywall = true
    }

    /** Shown once at the end of onboarding. Always dismissible. */
    fun openPaywallAfterOnboarding() {
        paywallReason = null
        paywallHeadline = "Unlock the whole universe"
        showPaywall = true
    }

    /** Subscribed on this device before but not Pro now (expired or cancelled). */
    val lapsed: Boolean get() = !isPro && prefs.getBoolean(PREF_HAD_SUB, false)

    private val client: BillingClient = BillingClient.newBuilder(context.applicationContext)
        .setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    fun start() {
        if (client.isReady) { refresh(); return }
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    refresh()
                } else {
                    loading = false
                }
            }
            override fun onBillingServiceDisconnected() { /* auto-reconnect enabled */ }
        })
    }

    fun end() { client.endConnection() }

    /** Re-query products and purchases. */
    fun refresh() {
        loadProducts()
        queryPurchases(userInitiated = false)
    }

    private fun loadProducts() {
        loading = true
        val subs = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(SUB_ID).setProductType(BillingClient.ProductType.SUBS).build()
        )).build()
        client.queryProductDetailsAsync(subs) { r, res ->
            if (r.responseCode == BillingClient.BillingResponseCode.OK) {
                subDetails = res.productDetailsList.firstOrNull()
            }
            loading = false
        }
        val inapp = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(LIFETIME_ID).setProductType(BillingClient.ProductType.INAPP).build()
        )).build()
        client.queryProductDetailsAsync(inapp) { r, res ->
            if (r.responseCode == BillingClient.BillingResponseCode.OK) {
                lifetimeDetails = res.productDetailsList.firstOrNull()
            }
        }
    }

    /** Restore = re-read owned purchases from Play. */
    fun restore() = queryPurchases(userInitiated = true)

    private fun queryPurchases(userInitiated: Boolean) {
        if (userInitiated) busy = true
        var pending = 2
        var found = false
        val done = {
            pending -= 1
            if (pending == 0) {
                updatePro(found)
                busy = false
                if (userInitiated && !found) {
                    message = "No BlackHole Pro purchase was found for this Google account."
                }
            }
        }
        for (type in listOf(BillingClient.ProductType.SUBS, BillingClient.ProductType.INAPP)) {
            client.queryPurchasesAsync(
                QueryPurchasesParams.newBuilder().setProductType(type).build()
            ) { r, purchases ->
                if (r.responseCode == BillingClient.BillingResponseCode.OK) {
                    purchases.forEach { if (handle(it)) found = true }
                } else if (r.responseCode != BillingClient.BillingResponseCode.OK) {
                    // Keep the cached entitlement when Play can't be reached.
                    if (isPro) found = true
                }
                done()
            }
        }
    }

    /** Returns true when the purchase grants Pro. Acknowledges new purchases. */
    private fun handle(p: Purchase): Boolean {
        val ours = p.products.any { it == SUB_ID || it == LIFETIME_ID }
        if (!ours || p.purchaseState != Purchase.PurchaseState.PURCHASED) return false
        if (p.products.contains(SUB_ID)) prefs.edit().putBoolean(PREF_HAD_SUB, true).apply()
        if (!p.isAcknowledged) {
            client.acknowledgePurchase(
                AcknowledgePurchaseParams.newBuilder().setPurchaseToken(p.purchaseToken).build()
            ) { }
        }
        return true
    }

    /** Debug-build override (see MainActivity.applyDebugProOverride). */
    private var debugOverride: Boolean? = null

    fun setDebugOverride(v: Boolean) {
        debugOverride = v
        isPro = v
    }

    private fun updatePro(v: Boolean) {
        debugOverride?.let { isPro = it; return }
        val wasPro = isPro
        isPro = v
        prefs.edit().putBoolean(PREF_KEY, v).apply()
        writeProFlag(v)
        if (v) showPaywall = false
        if (v && !wasPro) justUnlocked = true
    }

    /** True right after a purchase or restore unlocked Pro (for a thank-you moment). */
    var justUnlocked by mutableStateOf(false)

    private fun writeProFlag(v: Boolean) {
        runCatching {
            val f = java.io.File(context.filesDir, PRO_FLAG_FILE)
            if (v) f.writeText("1") else f.delete()
        }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        busy = false
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val granted = purchases.orEmpty().any { handle(it) }
                if (granted) updatePro(true)
                else if (purchases.orEmpty().any { it.purchaseState == Purchase.PurchaseState.PENDING }) {
                    message = "Your purchase is pending. Pro unlocks as soon as Google Play confirms the payment."
                }
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> queryPurchases(userInitiated = true)
            BillingClient.BillingResponseCode.USER_CANCELED -> Unit
            else -> message = "Purchase failed: ${result.debugMessage.ifBlank { "code ${result.responseCode}" }}"
        }
    }

    // ---- plans ----

    data class Plan(
        val key: String,            // "lifetime" | "yearly"
        val title: String,
        val price: String,          // price charged now (lifetime) or the recurring price
        val per: String,            // "once" | "per year"
        val trialDays: Int,         // 0 = no trial offered to this account
        val priceMicros: Long,
        val offerToken: String?,
        val details: ProductDetails,
        /** Subscription: discounted first-period price, e.g. "$11.99". */
        val introPrice: String? = null,
        /** Full terms, e.g. "1 week free, then $11.99 for the first year, then $17.99 per year". */
        val terms: String? = null,
        /** Lifetime sale: the regular price to strike through. */
        val fullPrice: String? = null,
        val percentOff: Int? = null,
        val saleEndsMillis: Long? = null,
        val winback: Boolean = false,
        /** "about $1.50 a month" (yearly only). */
        val perMonth: String? = null
    )

    /**
     * Plans shown on the paywall, lifetime first (the main offer), then
     * yearly with its best eligible offer. The monthly base plan stays active
     * on Play for existing subscribers but is not offered here.
     */
    fun plans(): List<Plan> {
        val out = mutableListOf<Plan>()
        lifetimeDetails?.let { d -> lifetimePlan(d)?.let { out += it } }
        subDetails?.let { d ->
            val offers = d.subscriptionOfferDetails.orEmpty().filter { it.basePlanId == PLAN_YEARLY }
            val infos = offers.map { o ->
                OfferInfo(o.offerId, o.offerTags, o.pricingPhases.pricingPhaseList.map { ph ->
                    PhaseInfo(ph.priceAmountMicros, ph.formattedPrice, ph.billingPeriod, ph.billingCycleCount,
                        ph.recurrenceMode != ProductDetails.RecurrenceMode.INFINITE_RECURRING)
                }, o.offerToken)
            }
            val chosen = OfferMath.choose(infos, lapsed) ?: return@let
            val rec = OfferMath.recurring(chosen)
            val intro = OfferMath.introPhase(chosen)
            val code = d.subscriptionOfferDetails.orEmpty().firstOrNull()
                ?.pricingPhases?.pricingPhaseList?.lastOrNull()?.priceCurrencyCode
            val perMonth = code?.let { c ->
                runCatching {
                    val nf = java.text.NumberFormat.getCurrencyInstance()
                    nf.currency = java.util.Currency.getInstance(c)
                    val m = nf.format(((intro ?: rec).priceMicros / 12) / 1_000_000.0)
                    if (intro != null) "about $m a month in the first year" else "about $m a month"
                }.getOrNull()
            }
            out += Plan(PLAN_YEARLY, "Yearly", rec.formatted, "per year",
                OfferMath.freeDays(chosen), rec.priceMicros, chosen.token, d,
                introPrice = OfferMath.introPhase(chosen)?.formatted,
                terms = OfferMath.describe(chosen),
                winback = OfferMath.isWinback(chosen),
                perMonth = perMonth)
        }
        return out
    }

    private fun lifetimePlan(d: ProductDetails): Plan? {
        val list = d.oneTimePurchaseOfferDetailsList.orEmpty()
        val base = list.firstOrNull { it.offerId == null } ?: d.oneTimePurchaseOfferDetails ?: list.firstOrNull()
        val best = list.minByOrNull { it.priceAmountMicros } ?: base ?: return null
        val now = System.currentTimeMillis()
        val window = best.validTimeWindow
        val live = window == null ||
            ((window.startTimeMillis ?: 0L) <= now && (window.endTimeMillis ?: Long.MAX_VALUE) > now)
        val o = if (live) best else (base ?: best)
        val onSale = base != null && o.priceAmountMicros < base.priceAmountMicros
        return Plan("lifetime", "Lifetime", o.formattedPrice, "once", 0, o.priceAmountMicros,
            o.offerToken, d,
            fullPrice = if (onSale) base!!.formattedPrice else null,
            percentOff = if (onSale) (o.discountDisplayInfo?.percentageDiscount
                ?: (100 - (o.priceAmountMicros * 100 / base!!.priceAmountMicros)).toInt()) else null,
            saleEndsMillis = if (onSale) o.validTimeWindow?.endTimeMillis else null)
    }

    fun buy(activity: Activity, plan: Plan) {
        val pp = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(plan.details)
        plan.offerToken?.let { pp.setOfferToken(it) }
        busy = true
        val r = client.launchBillingFlow(activity,
            BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(pp.build())).build())
        if (r.responseCode != BillingClient.BillingResponseCode.OK) {
            busy = false
            message = "Google Play couldn't start the purchase (${r.debugMessage.ifBlank { "code ${r.responseCode}" }})."
        }
    }
}
