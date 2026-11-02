package com.orchestrsim.blackhole.focus

/** Pomodoro state machine (pure, clock passed in), mirroring the iOS PomodoroTimer. */
enum class FocusPhase(val label: String) {
    IDLE("Ready"), WORKING("Focus"), SHORT_BREAK("Short Break"), LONG_BREAK("Long Break")
}

class FocusTimerCore(
    var workMinutes: Int = 25,
    var shortBreakMinutes: Int = 5,
    var longBreakMinutes: Int = 15,
    var sessionsBeforeLongBreak: Int = 4
) {
    var phase = FocusPhase.IDLE; internal set
    var remainingMs: Long = workMinutes * 60_000L; internal set
    /** Wall-clock end of the running phase; null while paused or idle. */
    var endAt: Long? = null; internal set
    var completedSessions = 0; internal set

    val isRunning: Boolean get() = endAt != null

    fun durationMs(p: FocusPhase): Long = when (p) {
        FocusPhase.IDLE, FocusPhase.WORKING -> workMinutes * 60_000L
        FocusPhase.SHORT_BREAK -> shortBreakMinutes * 60_000L
        FocusPhase.LONG_BREAK -> longBreakMinutes * 60_000L
    }

    fun start(now: Long) {
        if (phase == FocusPhase.IDLE) begin(FocusPhase.WORKING, now)
        else if (!isRunning) endAt = now + remainingMs
    }

    fun pause(now: Long) {
        val end = endAt ?: return
        remainingMs = (end - now).coerceAtLeast(0)
        endAt = null
    }

    fun reset() {
        phase = FocusPhase.IDLE
        remainingMs = workMinutes * 60_000L
        endAt = null
        completedSessions = 0
    }

    /** Skip to the next phase now. */
    fun skip(now: Long) { completePhase(now) }

    /** Advances the clock. Returns the phase that just finished, if any. */
    fun tick(now: Long): FocusPhase? {
        val end = endAt ?: return null
        if (now < end) { remainingMs = end - now; return null }
        val done = phase
        completePhase(now)
        return done
    }

    fun progress(now: Long): Float {
        val total = durationMs(phase).coerceAtLeast(1)
        val rem = endAt?.let { (it - now).coerceAtLeast(0) } ?: remainingMs
        return (1f - rem.toFloat() / total).coerceIn(0f, 1f)
    }

    fun remainingAt(now: Long): Long = endAt?.let { (it - now).coerceAtLeast(0) } ?: remainingMs

    /** Idle-state duration follows the focus length setting. */
    fun configChanged() { if (phase == FocusPhase.IDLE) remainingMs = workMinutes * 60_000L }

    private fun begin(p: FocusPhase, now: Long) {
        phase = p
        remainingMs = durationMs(p)
        endAt = now + remainingMs
    }

    private fun completePhase(now: Long) {
        when (phase) {
            FocusPhase.WORKING -> {
                completedSessions += 1
                val long = sessionsBeforeLongBreak > 0 && completedSessions % sessionsBeforeLongBreak == 0
                begin(if (long) FocusPhase.LONG_BREAK else FocusPhase.SHORT_BREAK, now)
            }
            FocusPhase.SHORT_BREAK, FocusPhase.LONG_BREAK -> begin(FocusPhase.WORKING, now)
            FocusPhase.IDLE -> Unit
        }
    }

    companion object {
        fun format(ms: Long): String {
            val total = ((ms + 999) / 1000).toInt()
            return "%02d:%02d".format(total / 60, total % 60)
        }
    }
}
