package com.orchestrsim.blackhole.focus

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.orchestrsim.blackhole.MainActivity
import com.orchestrsim.blackhole.R

/**
 * Pro focus (Pomodoro) timer over the simulation. State survives process
 * death (wall-clock end time in prefs); an inexact AlarmManager alarm posts
 * the end-of-phase notification when the app is in the background.
 */
class FocusTimer(private val ctx: Context) {
    private val prefs = ctx.getSharedPreferences("bh.focus", Context.MODE_PRIVATE)
    val core = FocusTimerCore(
        prefs.getInt("work", 25), prefs.getInt("short", 5),
        prefs.getInt("long", 15), prefs.getInt("every", 4)
    )
    /** Bumped on every change so Compose recomposes. */
    var version by mutableIntStateOf(0); private set

    init {
        core.phase = runCatching { FocusPhase.valueOf(prefs.getString("phase", "IDLE")!!) }.getOrDefault(FocusPhase.IDLE)
        core.remainingMs = prefs.getLong("remaining", core.durationMs(core.phase))
        core.endAt = prefs.getLong("endAt", 0L).takeIf { it > 0 }
        core.completedSessions = prefs.getInt("sessions", 0)
        tick()
    }

    fun start() { core.start(now()); changed() }
    fun pause() { core.pause(now()); changed() }
    fun reset() { core.reset(); changed() }
    fun skip() { core.skip(now()); changed() }

    fun setDurations(work: Int, short: Int, long: Int, every: Int) {
        core.workMinutes = work; core.shortBreakMinutes = short
        core.longBreakMinutes = long; core.sessionsBeforeLongBreak = every
        core.configChanged(); changed()
    }

    /** Called by the UI ticker; advances to the next phase when one ends. */
    fun tick() {
        if (core.tick(now()) != null) changed() else version++
    }

    private fun now() = System.currentTimeMillis()

    private fun changed() {
        prefs.edit()
            .putString("phase", core.phase.name).putLong("remaining", core.remainingMs)
            .putLong("endAt", core.endAt ?: 0L).putInt("sessions", core.completedSessions)
            .putInt("work", core.workMinutes).putInt("short", core.shortBreakMinutes)
            .putInt("long", core.longBreakMinutes).putInt("every", core.sessionsBeforeLongBreak)
            .apply()
        schedule()
        version++
    }

    private fun schedule() {
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return
        val pi = PendingIntent.getBroadcast(ctx, 41,
            Intent(ctx, FocusAlarmReceiver::class.java).putExtra("phase", core.phase.name),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        am.cancel(pi)
        val end = core.endAt ?: return
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, pi)
    }

    companion object {
        const val CHANNEL = "focus"

        fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = ctx.getSystemService(NotificationManager::class.java)
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Focus timer", NotificationManager.IMPORTANCE_HIGH)
                        .apply { description = "Tells you when a focus session or break ends." })
            }
        }
    }
}

/** Posts the end-of-phase notification. */
class FocusAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val phase = runCatching { FocusPhase.valueOf(intent.getStringExtra("phase") ?: "") }.getOrNull() ?: return
        val (title, body) = when (phase) {
            FocusPhase.WORKING -> "Focus session complete" to "Take a break. You've earned it."
            FocusPhase.SHORT_BREAK -> "Short break over" to "Back to focus when you're ready."
            FocusPhase.LONG_BREAK -> "Long break over" to "Ready for the next session?"
            FocusPhase.IDLE -> return
        }
        FocusTimer.ensureChannel(ctx)
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(ctx, FocusTimer.CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_timer)
            .setContentTitle(title).setContentText(body)
            .setContentIntent(open).setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        runCatching { NotificationManagerCompat.from(ctx).notify(42, n) }
    }
}
