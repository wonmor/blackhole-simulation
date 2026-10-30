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
 *  - subscription `blackhole_pro`, base plans `monthly` (P1M) and `yearly`
 *    (P1Y), each with a 1-week free-trial offer for new subscribers;
 *  - one-time product `blackhole_pro_lifetime`.
 *
 * Any active purchase of either unlocks Pro. The last known entitlement is
 * cached so Pro works offline; Play remains the source of truth and is
 * re-queried on every launch and resume.
 */
class ProManager(context: Context) : PurchasesUpdatedListener {

    companion object {
        const val SUB_ID = "blackhole_pro"
        const val LIFETIME_ID = "blackhole_pro_lifetime"
        const val PLAN_MONTHLY = "monthly"
        const val PLAN_YEARLY = "yearly"
        private const val PREF_KEY = "pro_cached"
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

    fun openPaywall(reason: String? = null) {
        paywallReason = reason
        showPaywall = true
    }

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
        isPro = v
        prefs.edit().putBoolean(PREF_KEY, v).apply()
        if (v) showPaywall = false
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
        val key: String,            // "yearly" | "monthly" | "lifetime"
        val title: String,
        val price: String,          // recurring or one-time price
        val per: String,            // "per year" | "per month" | "once"
        val trialDays: Int,         // 0 = no trial offered to this account
        val priceMicros: Long,
        val offerToken: String?,
        val details: ProductDetails
    )

    fun plans(): List<Plan> {
        val out = mutableListOf<Plan>()
        subDetails?.let { d ->
            for ((plan, title, per) in listOf(
                Triple(PLAN_YEARLY, "Yearly", "per year"),
                Triple(PLAN_MONTHLY, "Monthly", "per month")
            )) {
                val offers = d.subscriptionOfferDetails.orEmpty().filter { it.basePlanId == plan }
                if (offers.isEmpty()) continue
                // Play only returns offers this user is eligible for; prefer one
                // with a free phase (the trial), else the base plan itself.
                val trial = offers.firstOrNull { o ->
                    o.offerId != null && o.pricingPhases.pricingPhaseList.any { it.priceAmountMicros == 0L }
                }
                val chosen = trial ?: offers.firstOrNull { it.offerId == null } ?: offers.first()
                val recurring = chosen.pricingPhases.pricingPhaseList.last()
                val free = chosen.pricingPhases.pricingPhaseList.firstOrNull { it.priceAmountMicros == 0L }
                out += Plan(plan, title, recurring.formattedPrice, per,
                    free?.let { isoDays(it.billingPeriod) } ?: 0,
                    recurring.priceAmountMicros, chosen.offerToken, d)
            }
        }
        lifetimeDetails?.let { d ->
            d.oneTimePurchaseOfferDetails?.let { o ->
                out += Plan("lifetime", "Lifetime", o.formattedPrice, "once", 0, o.priceAmountMicros, null, d)
            }
        }
        return out
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

    private fun isoDays(p: String): Int {
        // P1W, P7D, P3D, P1M
        val m = Regex("P(\\d+)([DWMY])").find(p) ?: return 7
        val n = m.groupValues[1].toInt()
        return when (m.groupValues[2]) { "D" -> n; "W" -> n * 7; "M" -> n * 30; else -> n * 365 }
    }
}
