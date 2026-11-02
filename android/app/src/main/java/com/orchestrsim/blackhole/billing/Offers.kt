package com.orchestrsim.blackhole.billing

/**
 * Pure (Android-free) offer logic so it can be unit tested on the JVM.
 *
 * Play returns, per base plan, only the offers this account is eligible for.
 * For the yearly plan that can be: `trial-intro` (1 week free, then a
 * discounted first year, then the full price), the older `yearly-trial`
 * (1 week free, then full price), `winback` (a discounted first year, meant
 * for lapsed subscribers only; the Play API cannot target it, so the app
 * filters it), and the plain base plan.
 */
data class PhaseInfo(
    val priceMicros: Long,
    val formatted: String,
    val period: String,       // ISO 8601, e.g. P1W, P1Y
    val cycles: Int,          // billing cycles for a finite phase
    val finite: Boolean       // false = infinite recurring (the base price)
)

data class OfferInfo(
    val offerId: String?,
    val tags: List<String>,
    val phases: List<PhaseInfo>,
    val token: String
)

object OfferMath {
    fun isWinback(o: OfferInfo) = o.offerId == "winback" || "winback" in o.tags

    fun freePhase(o: OfferInfo): PhaseInfo? = o.phases.firstOrNull { it.priceMicros == 0L }

    fun freeDays(o: OfferInfo): Int = freePhase(o)?.let { isoDays(it.period) * maxOf(1, it.cycles) } ?: 0

    /** A discounted, finite paid phase before the recurring price. */
    fun introPhase(o: OfferInfo): PhaseInfo? {
        if (o.phases.size < 2) return null
        val rec = o.phases.last()
        return o.phases.dropLast(1).firstOrNull { it.priceMicros in 1 until rec.priceMicros }
    }

    fun recurring(o: OfferInfo): PhaseInfo = o.phases.last()

    /**
     * Best offer to show: the longest free trial, then the cheapest intro
     * price. Win-back offers are only considered for lapsed subscribers, and
     * for them they win (that is what they are for).
     */
    fun choose(offers: List<OfferInfo>, lapsed: Boolean): OfferInfo? {
        if (offers.isEmpty()) return null
        if (lapsed) offers.firstOrNull { isWinback(it) }?.let { return it }
        val pool = offers.filter { !isWinback(it) }.ifEmpty { return null }
        return pool.sortedWith(
            compareByDescending<OfferInfo> { freeDays(it) }
                .thenBy { introPhase(it)?.priceMicros ?: recurring(it).priceMicros }
                .thenBy { if (it.offerId == null) 1 else 0 }
        ).first()
    }

    /** "1 week free, then $11.99 for the first year, then $17.99 per year". */
    fun describe(o: OfferInfo): String {
        val parts = mutableListOf<String>()
        freePhase(o)?.let { parts += "${durationText(it.period, it.cycles)} free" }
        introPhase(o)?.let { parts += "${it.formatted} for the first ${durationText(it.period, it.cycles, first = true)}" }
        val rec = recurring(o)
        parts += "${rec.formatted} per ${unitText(rec.period)}"
        return parts.joinToString(", then ")
    }

    fun isoDays(p: String): Int {
        val m = Regex("P(\\d+)([DWMY])").find(p) ?: return 0
        val n = m.groupValues[1].toInt()
        return when (m.groupValues[2]) { "D" -> n; "W" -> n * 7; "M" -> n * 30; else -> n * 365 }
    }

    /** "1 week", "3 days", "2 months"; with first=true: "year", "3 months". */
    fun durationText(period: String, cycles: Int = 1, first: Boolean = false): String {
        val m = Regex("P(\\d+)([DWMY])").find(period) ?: return period
        var n = m.groupValues[1].toInt() * maxOf(1, cycles)
        var unit = when (m.groupValues[2]) { "D" -> "day"; "W" -> "week"; "M" -> "month"; else -> "year" }
        if (unit == "day" && n % 7 == 0) { n /= 7; unit = "week" }
        if (unit == "month" && n % 12 == 0) { n /= 12; unit = "year" }
        return when {
            first && n == 1 -> unit
            n == 1 -> "1 $unit"
            else -> "$n ${unit}s"
        }
    }

    fun unitText(period: String): String = durationText(period, 1, first = true)
}
