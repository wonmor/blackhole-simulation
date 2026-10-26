package com.orchestrsim.blackhole.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.NativeBridge
import com.orchestrsim.blackhole.model.SimState
import kotlin.math.abs
import kotlin.math.roundToInt

/** Top-left telemetry overlay. Kerr observables come from the Rust engine. */
@Composable
fun Hud(sim: SimState, fps: Float, scale: Float, modifier: Modifier = Modifier) {
    val m = sim.mass.toDouble()
    val a = (sim.spin * sim.mass).toDouble()   // shader uses a = spin * M
    val horizon = NativeBridge.nativeKerrHorizon(m, a)
    val photon = NativeBridge.nativeKerrPhotonSphere(m, a)
    val isco = NativeBridge.nativeKerrIsco(m, a, true)

    Column(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Color.Black.copy(alpha = 0.45f))
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        line("FPS", "${fps.roundToInt()}")
        line("Scale", "${(scale * 100).roundToInt()}%")
        line("r₊", fmt(horizon))
        line("Photon", fmt(photon))
        line("ISCO", fmt(isco))
        if (abs(sim.spin) > 0.001f) line("a*", fmt(sim.spin.toDouble()))
    }
}

@Composable
private fun line(label: String, value: String) {
    Text(
        "$label  $value",
        color = Color.White,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Monospace
    )
}

private fun fmt(x: Double): String = ((x * 100).roundToInt() / 100.0).toString()
