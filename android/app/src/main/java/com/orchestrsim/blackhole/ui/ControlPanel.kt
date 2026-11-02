package com.orchestrsim.blackhole.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.billing.ProManager
import com.orchestrsim.blackhole.focus.FocusPhase
import com.orchestrsim.blackhole.focus.FocusTimer
import com.orchestrsim.blackhole.focus.FocusTimerCore
import com.orchestrsim.blackhole.model.QualityPreset
import com.orchestrsim.blackhole.model.Scenario
import com.orchestrsim.blackhole.model.SimState

/**
 * Parameter editor, laid out like the iOS ControlPanel: header (About,
 * reset), quality picker, then collapsible Scenarios, Geometry, Accretion
 * disk, Bloom, Camera, Tools and Effects sections.
 *
 * Free: mass, spin, every disk slider, zoom, the effect toggles, Low to High
 * quality and four scenarios. Pro: Ultra and Cinematic, six scenarios, studio
 * tuning (lensing and frame-drag strength, bloom, camera auto-spin), the
 * focus timer, the live wallpaper and the 4K and video exports. Locked
 * controls show their value with a Pro tag; tapping one opens the paywall.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ControlPanel(
    sim: SimState,
    pro: ProManager,
    focus: FocusTimer,
    onLessons: () -> Unit,
    onExport: () -> Unit,
    onFocus: () -> Unit,
    onWallpaper: () -> Unit,
    onAbout: () -> Unit,
    onScenario: (Scenario) -> Unit,
    modifier: Modifier = Modifier
) {
    val locked = !pro.isPro
    val tick = rememberTick()
    val free = Gate(false) { }
    val studio = Gate(locked) { reason -> pro.openPaywall(reason) }

    Column(
        modifier.verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (locked) LockedBanner(pro)

        // Header
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Cyclone, contentDescription = null, tint = Accent, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("KERR PARAMETERS", color = Color.White.copy(alpha = 0.55f), fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp, modifier = Modifier.weight(1f))
            HeaderGlyph(Icons.Outlined.Info, "About BlackHole") { onAbout() }
            Spacer(Modifier.width(6.dp))
            HeaderGlyph(Icons.Outlined.RestartAlt, "Reset to defaults") { tick(); sim.resetToDefaults(pro.isPro) }
        }

        QualityPicker(sim, pro)

        Section("Scenarios", initiallyOpen = true) {
            Scenario.entries.filter { !it.isPro }.forEach { s -> ScenarioCard(s, false) { tick(); onScenario(s) } }
            Text(if (locked) "PRO SCENARIOS (UNLOCK WITH PRO)" else "PRO SCENARIOS",
                color = Color.White.copy(alpha = 0.45f), fontSize = 9.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.2.sp,
                modifier = Modifier.padding(top = 2.dp))
            Scenario.entries.filter { it.isPro }.forEach { s ->
                ScenarioCard(s, locked) {
                    if (locked) pro.openPaywall("The ${s.displayName} scenario") else { tick(); onScenario(s) }
                }
            }
        }

        Section("Geometry", initiallyOpen = true) {
            free.slider("Mass", sim.mass, 0.1f, 10f, "%.2f", "M☉") { sim.mass = it }
            free.slider("Spin", sim.spin, -0.99f, 0.99f, "%.2f", "a*") { sim.spin = it }
            studio.slider("Lensing", sim.lensingStrength, 0f, 2f, "%.2f", "η") { sim.lensingStrength = it }
            studio.slider("Frame drag", sim.frameDragStrength, 0f, 2f, "%.2f", "") { sim.frameDragStrength = it }
        }

        Section("Accretion disk", initiallyOpen = true) {
            free.slider("Size", sim.diskSize, 4f, 100f, "%.1f", "M") { sim.diskSize = it }
            free.slider("Density", sim.diskDensity, 0f, 5f, "%.2f", "") { sim.diskDensity = it }
            free.slider("Temperature", sim.diskTemp, 1000f, 50000f, "%.0f", "K") { sim.diskTemp = it }
            free.slider("Scale height", sim.diskScaleHeight, 0.01f, 0.30f, "%.2f", "H/R") { sim.diskScaleHeight = it }
            free.slider("Rotation speed", sim.diskSpeed, 0f, 4f, "%.2f", "x") { sim.diskSpeed = it }
        }

        Section("Bloom", initiallyOpen = false, pro = locked) {
            studio.slider("Threshold", sim.bloomThreshold, 0.2f, 3f, "%.2f", "") { sim.bloomThreshold = it }
            studio.slider("Intensity", sim.bloomIntensity, 0f, 1.5f, "%.2f", "") { sim.bloomIntensity = it }
        }

        Section("Camera", initiallyOpen = true) {
            free.slider("Zoom", sim.zoom, 1.5f, 100f, "%.1f", "M") { sim.zoom = it; sim.pushCamera() }
            studio.slider("Auto-spin", sim.autoSpin, -0.1f, 0.1f, "%.3f", "rad/s") { sim.autoSpin = it }
        }

        Section("Tools", initiallyOpen = true) {
            ToolRow(Icons.Outlined.School, "Lessons", if (locked) "2 free, 6 more with Pro" else "8 guided physics tours", false) { onLessons() }
            ToolRow(Icons.Outlined.Wallpaper, "Live wallpaper", "The black hole on your home screen", locked) {
                if (locked) pro.openPaywall("The live wallpaper") else onWallpaper()
            }
            @Suppress("UNUSED_VARIABLE") val v = focus.version
            val core = focus.core
            ToolRow(Icons.Outlined.Timer, "Focus timer",
                if (core.phase == FocusPhase.IDLE) "Pomodoro | 25 min default"
                else "${core.phase.label} | ${FocusTimerCore.format(core.remainingAt(System.currentTimeMillis()))}", locked) {
                if (locked) pro.openPaywall("The focus timer") else onFocus()
            }
            ToolRow(Icons.Outlined.Download, "Save and export",
                if (locked) "Screen frame free, 4K and video with Pro" else "Screen frame, 4K poster, orbit video", false) { onExport() }
        }

        Section("Effects", initiallyOpen = false) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                EffectChip("Lensing", sim.enableLensing) { sim.enableLensing = it }
                EffectChip("Disk", sim.enableDisk) { sim.enableDisk = it }
                EffectChip("Doppler", sim.enableDoppler) { sim.enableDoppler = it }
                EffectChip("Photon", sim.enablePhotonGlow) { sim.enablePhotonGlow = it }
                EffectChip("Stars", sim.enableStars) { sim.enableStars = it }
                EffectChip("Jets", sim.enableJets) { sim.enableJets = it }
                EffectChip("Redshift", sim.showRedshift) { sim.showRedshift = it }
            }
        }

        if (locked) {
            Button(
                onClick = { pro.openPaywall() },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.Black)
            ) { Text("See what Pro adds", fontWeight = FontWeight.SemiBold) }
            TextButton(onClick = { pro.restore() }, enabled = !pro.busy, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                Text("Restore purchases", color = Accent, fontSize = 12.sp)
            }
        }
        Spacer(Modifier.height(24.dp))
    }

    pro.message?.let { msg ->
        if (!pro.showPaywall) {
            AlertDialog(
                onDismissRequest = { pro.message = null },
                confirmButton = { TextButton(onClick = { pro.message = null }) { Text("OK", color = Accent) } },
                text = { Text(msg) }
            )
        }
    }
}

fun scenarioGlyph(s: Scenario): ImageVector = when (s) {
    Scenario.STELLAR -> Icons.Outlined.AutoAwesome
    Scenario.SGR_A -> Icons.Outlined.GpsFixed
    Scenario.MAXIMAL_SPIN -> Icons.Outlined.Refresh
    Scenario.SCHWARZSCHILD -> Icons.Outlined.Cyclone
    Scenario.M87 -> Icons.Outlined.CenterFocusWeak
    Scenario.GARGANTUA -> Icons.Outlined.Movie
    Scenario.RETROGRADE -> Icons.Outlined.UTurnLeft
    Scenario.CYGNUS_X1 -> Icons.Outlined.Bolt
    Scenario.QUASAR -> Icons.Outlined.LocalFireDepartment
    Scenario.BARE_SHADOW -> Icons.Outlined.Visibility
}

@Composable
private fun QualityPicker(sim: SimState, pro: ProManager) {
    val tick = rememberTick()
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        QualityPreset.entries.forEach { p ->
            val pLocked = p.isPro && !pro.isPro
            val sel = sim.preset == p
            Row(
                Modifier.weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (sel) Accent else Color.White.copy(alpha = 0.05f))
                    .border(BorderStroke(0.6.dp, if (sel) Color.Transparent else Color.White.copy(alpha = 0.10f)), RoundedCornerShape(8.dp))
                    .clickable(role = Role.Button) {
                        if (pLocked) pro.openPaywall(if (p == QualityPreset.CINEMATIC) "Cinematic ray tracing" else "Ultra quality")
                        else { tick(); sim.selectPreset(p) }
                    }
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(p.displayName.uppercase(), color = if (sel) Color.Black else Color.White.copy(alpha = 0.75f),
                    fontSize = 10.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                if (pLocked) {
                    Spacer(Modifier.width(2.dp))
                    Icon(Icons.Outlined.Lock, contentDescription = "Pro", tint = Color.White.copy(alpha = 0.75f), modifier = Modifier.size(9.dp))
                }
            }
        }
    }
}

@Composable
private fun Section(title: String, initiallyOpen: Boolean, pro: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    var open by rememberSaveable(title) { mutableStateOf(initiallyOpen) }
    val rot by animateFloatAsState(if (open) 90f else 0f, label = "chev")
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = Accent.copy(alpha = 0.85f),
                modifier = Modifier.size(14.dp).rotate(rot))
            Spacer(Modifier.width(6.dp))
            SectionLabel(title)
            if (pro) {
                Spacer(Modifier.width(6.dp))
                Icon(Icons.Outlined.Lock, contentDescription = "Pro", tint = Accent, modifier = Modifier.size(11.dp))
            }
        }
        AnimatedVisibility(open) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.07f)))
    }
}

@Composable
private fun HeaderGlyph(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(
        Modifier.clip(RoundedCornerShape(6.dp)).background(Color.White.copy(alpha = 0.06f))
            .border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.12f)), RoundedCornerShape(6.dp))
            .clickable(onClickLabel = label) { onClick() }.padding(7.dp)
    ) { Icon(icon, contentDescription = label, tint = Color.White.copy(alpha = 0.65f), modifier = Modifier.size(15.dp)) }
}

@Composable
private fun ScenarioCard(s: Scenario, locked: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(9.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.10f)), RoundedCornerShape(9.dp))
            .clickable(role = Role.Button) { onClick() }
            .padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(scenarioGlyph(s), contentDescription = null, tint = Accent.copy(alpha = 0.85f), modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(s.displayName, color = Color.White.copy(alpha = 0.95f), fontSize = 13.sp, fontWeight = FontWeight.Medium)
                if (locked) ProBadge()
            }
            Text(s.subtitle, color = Color.White.copy(alpha = 0.55f), fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        }
        Icon(if (locked) Icons.Outlined.Lock else Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = null,
            tint = Color.White.copy(alpha = 0.45f), modifier = Modifier.size(14.dp))
    }
}

@Composable
private fun ToolRow(icon: ImageVector, title: String, sub: String, locked: Boolean, onClick: () -> Unit) =
    OptionRow(icon, title, sub, locked, trailing = Icons.AutoMirrored.Outlined.ArrowForward, onClick = onClick)

@Composable
private fun EffectChip(label: String, on: Boolean, onChange: (Boolean) -> Unit) {
    FilterChip(selected = on, onClick = { onChange(!on) }, label = { Text(label, fontSize = 11.sp) },
        leadingIcon = if (on) { { Icon(Icons.Outlined.Check, contentDescription = null, modifier = Modifier.size(14.dp)) } } else null)
}

/** Locks a control for free users: it renders dimmed, and a tap opens the paywall. */
private class Gate(val locked: Boolean, val openPaywall: (String) -> Unit) {
    @Composable
    fun slider(label: String, value: Float, min: Float, max: Float, format: String, unit: String, onChange: (Float) -> Unit) {
        Box {
            Column {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(label, fontSize = 12.sp, color = Color.White.copy(alpha = 0.78f))
                    if (locked) { Spacer(Modifier.width(6.dp)); ProBadge() }
                    Spacer(Modifier.weight(1f))
                    ValueChip(format.format(value), unit)
                }
                Slider(
                    value = value.coerceIn(min, max), onValueChange = onChange, valueRange = min..max,
                    enabled = !locked, modifier = Modifier.height(30.dp),
                    colors = SliderDefaults.colors(
                        disabledThumbColor = Color.White.copy(alpha = 0.55f),
                        disabledActiveTrackColor = Accent.copy(alpha = 0.40f),
                        disabledInactiveTrackColor = Color.White.copy(alpha = 0.14f)
                    )
                )
            }
            if (locked) {
                Box(Modifier.matchParentSize().clickable(role = Role.Button, onClickLabel = "Unlock with Pro") {
                    openPaywall("Changing $label")
                })
            }
        }
    }
}

@Composable
private fun ValueChip(value: String, unit: String) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.05f))
            .border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.10f)), RoundedCornerShape(50))
            .padding(horizontal = 7.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(value, color = Color.White.copy(alpha = 0.92f), fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        if (unit.isNotEmpty()) {
            Spacer(Modifier.width(4.dp))
            Text(unit, color = Color.White.copy(alpha = 0.45f), fontSize = 10.sp)
        }
    }
}

@Composable
private fun LockedBanner(pro: ProManager) {
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Accent.copy(alpha = 0.10f))
            .border(0.8.dp, Accent.copy(alpha = 0.45f), RoundedCornerShape(12.dp))
            .clickable { pro.openPaywall() }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(Icons.Outlined.AutoAwesome, contentDescription = null, tint = Accent, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f)) {
            Text("Mass, spin and the disk are free", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text("Pro adds the live wallpaper, 4K and video export, Ultra and Cinematic, six scenarios, six lessons, the focus timer and studio tuning.",
                fontSize = 11.sp, color = Color.White.copy(alpha = 0.75f))
        }
        ProBadge()
    }
}
