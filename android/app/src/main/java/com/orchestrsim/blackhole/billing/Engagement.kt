package com.orchestrsim.blackhole.billing

import android.content.Context
import android.os.SystemClock

/**
 * Decides when to show the one-time "wow" paywall and when to ask for a Play
 * rating. Nothing here fires on first touch: the paywall waits until the user
 * has had a few good moments (a scenario, a finished lesson, a saved
 * snapshot) and at least 45 seconds with the simulator; the rating prompt
 * only follows a finished lesson or a saved snapshot. Play applies its own
 * quota on top of the local 10-day spacing.
 */
class Engagement(context: Context) {
    enum class Moment { SCENARIO, LESSON_DONE, SNAPSHOT }
    enum class Action { NONE, PAYWALL, REVIEW }

    private val prefs = context.getSharedPreferences("bh.engage", Context.MODE_PRIVATE)
    private val sessionStart = SystemClock.elapsedRealtime()

    fun onMoment(m: Moment, isPro: Boolean): Action {
        val count = prefs.getInt("moments", 0) + 1
        prefs.edit().putInt("moments", count).apply()

        val sessionSec = (SystemClock.elapsedRealtime() - sessionStart) / 1000
        if (!isPro && !prefs.getBoolean("wowShown", false) && count >= 3 && sessionSec >= 45) {
            prefs.edit().putBoolean("wowShown", true).apply()
            return Action.PAYWALL
        }
        if (m == Moment.SCENARIO) return Action.NONE
        val now = System.currentTimeMillis()
        val last = prefs.getLong("reviewAskedAt", 0L)
        if (now - last < 10L * 24 * 3600 * 1000) return Action.NONE
        prefs.edit().putLong("reviewAskedAt", now).apply()
        return Action.REVIEW
    }
}
