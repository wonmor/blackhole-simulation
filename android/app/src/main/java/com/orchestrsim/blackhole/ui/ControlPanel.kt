package com.orchestrsim.blackhole.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.model.QualityPreset
import com.orchestrsim.blackhole.model.Scenario
import com.orchestrsim.blackhole.model.SimState

/** Scrollable controls: scenarios, quality, geometry/disk sliders, toggles. */
@Composable
fun ControlPanel(sim: SimState, modifier: Modifier = Modifier) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        section("Scenarios")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Scenario.entries.forEach { s ->
                AssistChip(
                    onClick = { sim.applyScenario(s) },
                    label = { Text(s.displayName, fontSize = 11.sp) }
                )
            }
        }

        section("Quality")
        SingleChoiceSegmented(
            options = QualityPreset.entries.map { it.displayName },
            selectedIndex = QualityPreset.entries.indexOf(sim.preset),
            onSelect = { sim.selectPreset(QualityPreset.entries[it]) }
        )

        section("Geometry")
        slider("Mass", sim.mass, 0.1f, 20.0f) { sim.mass = it }
        slider("Spin a*", sim.spin, 0.0f, 0.99f) { sim.spin = it }
        slider("Lensing", sim.lensingStrength, 0.0f, 2.0f) { sim.lensingStrength = it }
        slider("Frame drag", sim.frameDragStrength, 0.0f, 4.0f) { sim.frameDragStrength = it }

        section("Accretion disk")
        slider("Density", sim.diskDensity, 0.0f, 10.0f) { sim.diskDensity = it }
        slider("Temp (K)", sim.diskTemp, 2000.0f, 25000.0f) { sim.diskTemp = it }
        slider("Size", sim.diskSize, 10.0f, 120.0f) { sim.diskSize = it }
        slider("Scale height", sim.diskScaleHeight, 0.05f, 0.45f) { sim.diskScaleHeight = it }

        section("Bloom")
        slider("Threshold", sim.bloomThreshold, 0.0f, 4.0f) { sim.bloomThreshold = it }
        slider("Intensity", sim.bloomIntensity, 0.0f, 2.0f) { sim.bloomIntensity = it }

        section("Camera")
        slider("Auto-spin", sim.autoSpin, -0.05f, 0.05f) { sim.autoSpin = it }

        section("Features")
        toggle("Gravitational lensing", sim.enableLensing) { sim.enableLensing = it }
        toggle("Accretion disk", sim.enableDisk) { sim.enableDisk = it }
        toggle("Doppler beaming", sim.enableDoppler) { sim.enableDoppler = it }
        toggle("Photon ring", sim.enablePhotonGlow) { sim.enablePhotonGlow = it }
        toggle("Starfield", sim.enableStars) { sim.enableStars = it }
        toggle("Relativistic jets", sim.enableJets) { sim.enableJets = it }
        toggle("Redshift view", sim.showRedshift) { sim.showRedshift = it }
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
        Slider(value = value, onValueChange = onChange, valueRange = min..max)
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

@Composable
private fun SingleChoiceSegmented(
    options: List<String>, selectedIndex: Int, onSelect: (Int) -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEachIndexed { i, label ->
            FilterChip(
                selected = i == selectedIndex,
                onClick = { onSelect(i) },
                label = { Text(label, fontSize = 11.sp) }
            )
        }
    }
}

private fun formatVal(v: Float): String =
    if (v >= 100f) v.toInt().toString() else ((v * 100).toInt() / 100.0).toString()
