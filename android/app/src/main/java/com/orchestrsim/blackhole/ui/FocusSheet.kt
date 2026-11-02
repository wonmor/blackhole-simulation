package com.orchestrsim.blackhole.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.focus.FocusPhase
import com.orchestrsim.blackhole.focus.FocusTimer
import com.orchestrsim.blackhole.focus.FocusTimerCore
import kotlinx.coroutines.delay

/** Pro focus timer: progress ring, Start/Pause, reset, skip, stats and
 *  durations. Same layout and colours as the iOS PomodoroView. */
@Composable
fun FocusContent(timer: FocusTimer, onClose: () -> Unit, onFirstStart: () -> Unit) {
    var showSettings by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { while (true) { timer.tick(); delay(500) } }
    @Suppress("UNUSED_VARIABLE") val v = timer.version   // recompose on change
    val core = timer.core
    val now = System.currentTimeMillis()
    val color = when (core.phase) {
        FocusPhase.IDLE, FocusPhase.WORKING -> Accent
        FocusPhase.SHORT_BREAK -> Amber
        FocusPhase.LONG_BREAK -> Violet
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            SectionLabel("Focus timer", Modifier.weight(1f))
            CloseButton(onClose)
        }
        Box(Modifier.size(220.dp), contentAlignment = Alignment.Center) {
            val p = core.progress(now)
            Canvas(Modifier.fillMaxSize()) {
                val sw = 14.dp.toPx()
                drawArc(Color.White.copy(alpha = 0.08f), 0f, 360f, false, style = Stroke(sw),
                    topLeft = androidx.compose.ui.geometry.Offset(sw / 2, sw / 2),
                    size = androidx.compose.ui.geometry.Size(size.width - sw, size.height - sw))
                if (p > 0.002f) drawArc(color, -90f, 360f * p, false, style = Stroke(sw, cap = StrokeCap.Round),
                    topLeft = androidx.compose.ui.geometry.Offset(sw / 2, sw / 2),
                    size = androidx.compose.ui.geometry.Size(size.width - sw, size.height - sw))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(FocusTimerCore.format(core.remainingAt(now)), color = Color.White, fontSize = 52.sp, fontWeight = FontWeight.Bold)
                Text(core.phase.label.uppercase(), color = color, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 2.sp)
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SmallGlyph(Icons.Outlined.RestartAlt, "Reset") { timer.reset() }
            Button(
                onClick = {
                    if (core.isRunning) timer.pause() else { onFirstStart(); timer.start() }
                },
                modifier = Modifier.weight(1f).height(46.dp), shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = Color.Black)
            ) {
                Text(when {
                    core.isRunning -> "Pause"
                    core.phase == FocusPhase.IDLE -> "Start Focus"
                    else -> "Resume"
                }, fontWeight = FontWeight.SemiBold)
            }
            SmallGlyph(Icons.Outlined.SkipNext, "Skip") { timer.skip() }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Stat("Sessions", "${core.completedSessions}")
            Spacer(Modifier.width(20.dp))
            val every = core.sessionsBeforeLongBreak.coerceAtLeast(1)
            Stat("Until long break", "${every - (core.completedSessions % every)}")
            Spacer(Modifier.weight(1f))
            SmallGlyph(if (showSettings) Icons.Outlined.ExpandLess else Icons.Outlined.Tune, "Durations") { showSettings = !showSettings }
        }
        AnimatedVisibility(showSettings) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                fun set(w: Int = core.workMinutes, s: Int = core.shortBreakMinutes, l: Int = core.longBreakMinutes, e: Int = core.sessionsBeforeLongBreak) =
                    timer.setDurations(w, s, l, e)
                Stepper("Focus", core.workMinutes, 5..90, "min") { set(w = it) }
                Stepper("Short break", core.shortBreakMinutes, 1..30, "min") { set(s = it) }
                Stepper("Long break", core.longBreakMinutes, 5..60, "min") { set(l = it) }
                Stepper("Long break every", core.sessionsBeforeLongBreak, 2..8, "sessions") { set(e = it) }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun SmallGlyph(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    OutlinedIconButton(onClick = onClick, shape = RoundedCornerShape(10.dp),
        border = BorderStroke(0.6.dp, Color.White.copy(alpha = 0.12f)),
        colors = IconButtonDefaults.outlinedIconButtonColors(containerColor = Color.White.copy(alpha = 0.06f))) {
        Icon(icon, contentDescription = label, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun Stat(label: String, value: String) {
    Column {
        Text(value, color = Color.White.copy(alpha = 0.92f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Text(label.uppercase(), color = Color.White.copy(alpha = 0.45f), fontSize = 8.sp, letterSpacing = 1.sp)
    }
}

@Composable
private fun Stepper(label: String, value: Int, range: IntRange, suffix: String, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Color.White.copy(alpha = 0.78f), fontSize = 12.sp, modifier = Modifier.weight(1f))
        IconButton(onClick = { if (value > range.first) onChange(value - 1) }) {
            Icon(Icons.Outlined.Remove, contentDescription = "Less", tint = Color.White.copy(alpha = 0.7f))
        }
        Text("$value $suffix", color = Color.White.copy(alpha = 0.92f), fontSize = 12.sp, fontFamily = FontFamily.Monospace)
        IconButton(onClick = { if (value < range.last) onChange(value + 1) }) {
            Icon(Icons.Outlined.Add, contentDescription = "More", tint = Color.White.copy(alpha = 0.7f))
        }
    }
}
