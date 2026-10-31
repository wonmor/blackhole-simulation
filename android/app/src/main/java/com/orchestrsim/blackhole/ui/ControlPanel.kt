package com.orchestrsim.blackhole.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.billing.ProManager
import com.orchestrsim.blackhole.model.QualityPreset
import com.orchestrsim.blackhole.model.Scenario
import com.orchestrsim.blackhole.model.SimState

/**
 * Scrollable controls: scenarios, quality, black-hole and disk sliders, toggles.
 *
 * Free: mass, spin, every accretion-disk slider (including rotation speed),
 * the effect toggles, Low to High quality and the four free scenarios.
 * Pro: Ultra and Cinematic quality, six more scenarios, and the studio tuning
 * (lensing and frame-drag strength, bloom, camera auto-spin). Locked controls
 * show their value with a lock glyph and "Pro" tag; tapping one opens the
 * paywall.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ControlPanel(
    sim: SimState,
    pro: ProManager,
    onLessons: () -> Unit,
    onSnapshot: () -> Unit,
    onScenario: (Scenario) -> Unit,
    modifier: Modifier = Modifier
) {
    val locked = !pro.isPro
    val free = Gate(false) { }
    val studio = Gate(locked) { reason -> pro.openPaywall(reason) }

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        if (locked) LockedBanner(pro)

        section("Tools")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AssistChip(onClick = onLessons, label = {
                Text(if (pro.isPro) "Lessons (8)" else "Lessons (2 free)", fontSize = 11.sp)
            })
            AssistChip(onClick = onSnapshot, label = { Text("Save snapshot", fontSize = 11.sp) })
        }

        section("Scenarios")
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp)
        ) {
            Scenario.entries.forEach { s ->
                val sLocked = s.isPro && locked
                AssistChip(
                    onClick = {
                        if (sLocked) pro.openPaywall("The ${s.displayName} scenario")
                        else onScenario(s)
                    },
                    label = { Text(s.displayName, fontSize = 11.sp) },
                    trailingIcon = if (sLocked) {
                        { LockGlyph() }
                    } else null
                )
            }
        }

        section("Quality")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            QualityPreset.entries.forEach { p ->
                val pLocked = p.isPro && locked
                FilterChip(
                    selected = sim.preset == p,
                    onClick = {
                        if (pLocked) pro.openPaywall(if (p == QualityPreset.CINEMATIC) "Cinematic ray tracing" else "Ultra quality")
                        else sim.selectPreset(p)
                    },
                    label = { Text(p.displayName, fontSize = 11.sp) },
                    trailingIcon = if (pLocked) {
                        { LockGlyph() }
                    } else null
                )
            }
        }

        section("Black hole")
        free.slider("Mass", sim.mass, 0.1f, 20.0f) { sim.mass = it }
        free.slider("Spin a*", sim.spin, -0.99f, 0.99f) { sim.spin = it }

        section("Accretion disk")
        free.slider("Rotation speed", sim.diskSpeed, 0.0f, 4.0f, suffix = "x") { sim.diskSpeed = it }
        free.slider("Density", sim.diskDensity, 0.0f, 10.0f) { sim.diskDensity = it }
        free.slider("Temperature (K)", sim.diskTemp, 1000.0f, 50000.0f) { sim.diskTemp = it }
        free.slider("Size", sim.diskSize, 4.0f, 120.0f) { sim.diskSize = it }
        free.slider("Scale height", sim.diskScaleHeight, 0.01f, 0.45f) { sim.diskScaleHeight = it }

        section("Effects")
        free.toggle("Lensing", sim.enableLensing) { sim.enableLensing = it }
        free.toggle("Disk", sim.enableDisk) { sim.enableDisk = it }
        free.toggle("Doppler", sim.enableDoppler) { sim.enableDoppler = it }
        free.toggle("Photon ring", sim.enablePhotonGlow) { sim.enablePhotonGlow = it }
        free.toggle("Stars", sim.enableStars) { sim.enableStars = it }
        free.toggle("Jets", sim.enableJets) { sim.enableJets = it }
        free.toggle("Redshift", sim.showRedshift) { sim.showRedshift = it }

        section("Studio tuning", locked)
        studio.slider("Lensing strength", sim.lensingStrength, 0.0f, 2.0f) { sim.lensingStrength = it }
        studio.slider("Frame drag", sim.frameDragStrength, 0.0f, 4.0f) { sim.frameDragStrength = it }
        studio.slider("Bloom threshold", sim.bloomThreshold, 0.0f, 4.0f) { sim.bloomThreshold = it }
        studio.slider("Bloom intensity", sim.bloomIntensity, 0.0f, 2.0f) { sim.bloomIntensity = it }
        studio.slider("Camera auto-spin", sim.autoSpin, -0.05f, 0.05f) { sim.autoSpin = it }

        if (locked) {
            Button(
                onClick = { pro.openPaywall() },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.Black)
            ) { Text("See what Pro adds", fontWeight = FontWeight.SemiBold) }
            RestoreButton(pro, Modifier.align(Alignment.CenterHorizontally))
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

/** Locks a control for free users: it renders disabled, and a tap opens the paywall. */
private class Gate(val locked: Boolean, val openPaywall: (String) -> Unit) {

    @Composable
    fun slider(label: String, value: Float, min: Float, max: Float, suffix: String = "", onChange: (Float) -> Unit) {
        Locked(label) {
            Column {
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    LabelWithLock(label)
                    Text(formatVal(value) + suffix, fontSize = 12.sp, color = Accent)
                }
                Slider(
                    value = value.coerceIn(min, max),
                    onValueChange = onChange,
                    valueRange = min..max,
                    enabled = !locked,
                    colors = SliderDefaults.colors(
                        disabledThumbColor = Color.White.copy(alpha = 0.55f),
                        disabledActiveTrackColor = Accent.copy(alpha = 0.40f),
                        disabledInactiveTrackColor = Color.White.copy(alpha = 0.14f)
                    )
                )
            }
        }
    }

    @Composable
    fun toggle(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
        Locked(label) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                LabelWithLock(label)
                Switch(
                    checked = checked,
                    onCheckedChange = onChange,
                    enabled = !locked,
                    colors = SwitchDefaults.colors(
                        disabledCheckedTrackColor = Accent.copy(alpha = 0.40f),
                        disabledCheckedThumbColor = Color.White.copy(alpha = 0.75f),
                        disabledUncheckedTrackColor = Color.White.copy(alpha = 0.06f),
                        disabledUncheckedThumbColor = Color.White.copy(alpha = 0.45f),
                        disabledUncheckedBorderColor = Color.White.copy(alpha = 0.30f)
                    )
                )
            }
        }
    }

    @Composable
    private fun LabelWithLock(label: String) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label, fontSize = 12.sp)
            if (locked) ProTag()
        }
    }

    /** Wraps a control; when locked, a transparent layer above it catches taps and drags. */
    @Composable
    private fun Locked(label: String, content: @Composable () -> Unit) {
        Box {
            content()
            if (locked) {
                Box(
                    Modifier
                        .matchParentSize()
                        .clickable(role = Role.Button, onClickLabel = "Unlock with Pro") {
                            openPaywall("Changing $label")
                        }
                )
            }
        }
    }
}

@Composable
private fun LockedBanner(pro: ProManager) {
    Row(
        Modifier
            .fillMaxWidth()
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
            Text(
                "Pro adds Ultra and Cinematic quality, six scenarios, six lessons and studio tuning.",
                fontSize = 11.sp, color = Color.White.copy(alpha = 0.75f)
            )
        }
        ProTag()
    }
}

@Composable
private fun RestoreButton(pro: ProManager, modifier: Modifier = Modifier) {
    TextButton(onClick = { pro.restore() }, enabled = !pro.busy, modifier = modifier) {
        Text("Restore purchases", color = Accent, fontSize = 12.sp)
    }
}

/** Small "Pro" tag with a lock glyph. */
@Composable
private fun ProTag() {
    Row(
        Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(Accent)
            .padding(horizontal = 5.dp, vertical = 1.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Icon(Icons.Outlined.Lock, contentDescription = null, tint = Color.Black, modifier = Modifier.size(9.dp))
        Text("Pro", color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun LockGlyph() =
    Icon(Icons.Outlined.Lock, contentDescription = "Pro", modifier = Modifier.size(14.dp))

@Composable
private fun section(title: String, locked: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, color = Accent, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
        if (locked) Icon(Icons.Outlined.Lock, contentDescription = "Pro", tint = Accent, modifier = Modifier.size(13.dp))
    }
}

private fun formatVal(v: Float): String =
    if (kotlin.math.abs(v) >= 100f) v.toInt().toString() else ((v * 100).toInt() / 100.0).toString()
