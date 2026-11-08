package com.orchestrsim.blackhole

import com.orchestrsim.blackhole.billing.OfferInfo
import com.orchestrsim.blackhole.billing.OfferMath
import com.orchestrsim.blackhole.billing.PhaseInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OfferMathTest {
    private val free = PhaseInfo(0, "Free", "P1W", 1, true)
    private val intro = PhaseInfo(11_990_000, "$11.99", "P1Y", 1, true)
    private val full = PhaseInfo(17_990_000, "$17.99", "P1Y", 0, false)

    private val base = OfferInfo(null, emptyList(), listOf(full), "base")
    private val trial = OfferInfo("yearly-trial", emptyList(), listOf(free, full), "trial")
    private val trialIntro = OfferInfo("trial-intro", listOf("intro", "trial"), listOf(free, intro, full), "ti")
    private val winback = OfferInfo("winback", listOf("winback"), listOf(intro, full), "wb")

    @Test fun picksTrialWithIntroOverPlainTrial() {
        assertEquals("ti", OfferMath.choose(listOf(base, trial, trialIntro, winback), lapsed = false)!!.token)
        assertEquals("ti", OfferMath.choose(listOf(trial, trialIntro), lapsed = false)!!.token)
    }

    @Test fun winbackOnlyForLapsed() {
        assertEquals("base", OfferMath.choose(listOf(base, winback), lapsed = false)!!.token)
        assertEquals("wb", OfferMath.choose(listOf(base, winback), lapsed = true)!!.token)
        assertNull(OfferMath.choose(listOf(winback), lapsed = false))
    }

    @Test fun describesPhases() {
        assertEquals("1 week free, then $11.99 for the first year, then $17.99 per year", OfferMath.describe(trialIntro))
        assertEquals("1 week free, then $17.99 per year", OfferMath.describe(trial))
        assertEquals("$17.99 per year", OfferMath.describe(base))
        assertEquals(7, OfferMath.freeDays(trialIntro))
        assertEquals("$11.99", OfferMath.introPhase(winback)!!.formatted)
        assertNull(OfferMath.introPhase(trial))
    }

    // Monthly base plan as configured on Play: base $4.99/month + "monthly-trial" (1 week free).
    private val mFull = PhaseInfo(4_990_000, "$4.99", "P1M", 0, false)
    private val mBase = OfferInfo(null, emptyList(), listOf(mFull), "m-base")
    private val mTrial = OfferInfo("monthly-trial", emptyList(), listOf(free, mFull), "m-trial")

    @Test fun monthlyPlanPicksTrialWhenEligible() {
        assertEquals("m-trial", OfferMath.choose(listOf(mBase, mTrial), lapsed = false)!!.token)
        // Play omits offers the account isn't eligible for: base plan alone still yields a plan.
        assertEquals("m-base", OfferMath.choose(listOf(mBase), lapsed = true)!!.token)
        assertEquals("1 week free, then $4.99 per month", OfferMath.describe(mTrial))
        assertEquals("$4.99 per month", OfferMath.describe(mBase))
        assertEquals(7, OfferMath.freeDays(mTrial))
    }

    @Test fun durations() {
        assertEquals("1 week", OfferMath.durationText("P7D"))
        assertEquals("3 days", OfferMath.durationText("P3D"))
        assertEquals("year", OfferMath.unitText("P12M"))
        assertEquals("2 weeks", OfferMath.durationText("P1W", 2))
    }
}
