package com.orchestrsim.blackhole.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.billing.ProManager
import com.orchestrsim.blackhole.model.QualityPreset
import com.orchestrsim.blackhole.model.Scenario
import com.orchestrsim.blackhole.model.SimState

/** Scrollable controls: scenarios, quality, geometry/disk sliders, toggles. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ControlPanel(
    sim: SimState,
    pro: ProManager,
    onLessons: () -> Unit,
    onSnapshot: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
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
                val locked = s.isPro && !pro.isPro
                AssistChip(
                    onClick = {
                        if (locked) pro.openPaywall("The ${s.displayName} scenario")
                        else sim.applyScenario(s)
                    },
                    label = { Text(s.displayName, fontSize = 11.sp) },
                    trailingIcon = if (locked) {
                        { Icon(Icons.Outlined.Lock, contentDescription = "Pro", modifier = Modifier.size(14.dp)) }
                    } else null
                )
            }
        }

        section("Quality")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            QualityPreset.entries.forEach { p ->
                val locked = p.isPro && !pro.isPro
                FilterChip(
                    selected = sim.preset == p,
                    onClick = {
                        if (locked) pro.openPaywall("Cinematic ray tracing") else sim.selectPreset(p)
                    },
                    label = { Text(p.displayName, fontSize = 11.sp) },
                    trailingIcon = if (locked) {
                        { Icon(Icons.Outlined.Lock, contentDescription = "Pro", modifier = Modifier.size(14.dp)) }
                    } else null
                )
            }
        }

        section("Geometry")
        slider("Mass", sim.mass, 0.1f, 20.0f) { sim.mass = it }
        slider("Spin a*", sim.spin, -0.99f, 0.99f) { sim.spin = it }
        slider("Lensing", sim.lensingStrength, 0.0f, 2.0f) { sim.lensingStrength = it }
        slider("Frame drag", sim.frameDragStrength, 0.0f, 4.0f) { sim.frameDragStrength = it }

        section("Accretion disk")
        slider("Density", sim.diskDensity, 0.0f, 10.0f) { sim.diskDensity = it }
        slider("Temperature (K)", sim.diskTemp, 1000.0f, 50000.0f) { sim.diskTemp = it }
        slider("Size", sim.diskSize, 4.0f, 120.0f) { sim.diskSize = it }
        slider("Scale height", sim.diskScaleHeight, 0.01f, 0.45f) { sim.diskScaleHeight = it }

        section("Bloom")
        slider("Threshold", sim.bloomThreshold, 0.0f, 4.0f) { sim.bloomThreshold = it }
        slider("Intensity", sim.bloomIntensity, 0.0f, 2.0f) { sim.bloomIntensity = it }

        section("Camera")
        slider("Auto-spin", sim.autoSpin, -0.05f, 0.05f) { sim.autoSpin = it }

        section("Effects")
        toggle("Lensing", sim.enableLensing) { sim.enableLensing = it }
        toggle("Disk", sim.enableDisk) { sim.enableDisk = it }
        toggle("Doppler", sim.enableDoppler) { sim.enableDoppler = it }
        toggle("Photon ring", sim.enablePhotonGlow) { sim.enablePhotonGlow = it }
        toggle("Stars", sim.enableStars) { sim.enableStars = it }
        toggle("Jets", sim.enableJets) { sim.enableJets = it }
        toggle("Redshift", sim.showRedshift) { sim.showRedshift = it }

        if (!pro.isPro) {
            Button(
                onClick = { pro.openPaywall() },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.Black)
            ) { Text("See BlackHole Pro", fontWeight = FontWeight.SemiBold) }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun section(title: String) =
    Text(title, color = Accent, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)

@Composable
private fun slider(
    label: String, value: Float, min: Float, max: Float, onChange: (Float) -> Unit
) {
    Column {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(label, fontSize = 12.sp)
            Text(formatVal(value), fontSize = 12.sp, color = Accent)
        }
        Slider(value = value.coerceIn(min, max), onValueChange = onChange, valueRange = min..max)
    }
}

@Composable
private fun toggle(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, fontSize = 12.sp)
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

private fun formatVal(v: Float): String =
    if (kotlin.math.abs(v) >= 100f) v.toInt().toString() else ((v * 100).toInt() / 100.0).toString()
