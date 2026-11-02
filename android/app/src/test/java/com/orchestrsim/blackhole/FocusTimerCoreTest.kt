package com.orchestrsim.blackhole

import com.orchestrsim.blackhole.focus.FocusPhase
import com.orchestrsim.blackhole.focus.FocusTimerCore
import org.junit.Assert.*
import org.junit.Test

class FocusTimerCoreTest {
    private val min = 60_000L

    @Test fun fullCycleWithLongBreak() {
        val t = FocusTimerCore(25, 5, 15, 2)
        var now = 0L
        t.start(now)
        assertEquals(FocusPhase.WORKING, t.phase)
        now += 25 * min; assertEquals(FocusPhase.WORKING, t.tick(now))
        assertEquals(FocusPhase.SHORT_BREAK, t.phase); assertEquals(1, t.completedSessions)
        now += 5 * min; t.tick(now)
        assertEquals(FocusPhase.WORKING, t.phase)
        now += 25 * min; t.tick(now)
        assertEquals(FocusPhase.LONG_BREAK, t.phase); assertEquals(2, t.completedSessions)
    }

    @Test fun pauseAndResumeKeepsRemaining() {
        val t = FocusTimerCore()
        t.start(0)
        t.pause(10 * min)
        assertFalse(t.isRunning)
        assertEquals(15 * min, t.remainingAt(99 * min))
        t.start(100 * min)
        assertEquals(115 * min, t.endAt)
        assertEquals("15:00", FocusTimerCore.format(t.remainingAt(100 * min)))
    }

    @Test fun resetAndSkip() {
        val t = FocusTimerCore()
        t.start(0); t.skip(1000)
        assertEquals(FocusPhase.SHORT_BREAK, t.phase)
        t.reset()
        assertEquals(FocusPhase.IDLE, t.phase); assertEquals(0, t.completedSessions); assertNull(t.endAt)
        t.workMinutes = 50; t.configChanged()
        assertEquals("50:00", FocusTimerCore.format(t.remainingAt(0)))
        assertEquals(0f, t.progress(0), 0.0001f)
    }
}
