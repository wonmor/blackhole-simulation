package com.orchestrsim.blackhole.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Functions
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.NativeBridge
import com.orchestrsim.blackhole.model.SimState
import kotlin.math.roundToInt

/**
 * Floating HUD, ported from the iOS HUDView: frame rate and pipeline tags,
 * live Kerr radii from the Rust gravitas engine, and an EQS panel listing
 * every closed-form equation the renderer evaluates, with citations.
 */
@Composable
fun Hud(
    sim: SimState, fps: Float, frameMs: Float, scale: Float,
    showMath: Boolean, onToggleMath: () -> Unit, modifier: Modifier = Modifier
) {
    val m = sim.mass.toDouble()
    val a = (sim.spin * sim.mass).toDouble()   // shader uses a = spin * M
    val rh = NativeBridge.nativeKerrHorizon(m, a)
    val rph = NativeBridge.nativeKerrPhotonSphere(m, a)
    val isco = NativeBridge.nativeKerrIsco(m, a, true)

    // Never run under the three top-right buttons (3 x 40 dp + gaps + margins).
    val room = (androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp - 24 - 136 - 8).coerceAtLeast(180)
    Column(
        modifier
            .width((if (showMath) 300 else 196).coerceAtMost(room).dp)
            .glassPanel()
            .animateContentSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.MonitorHeart, contentDescription = null, tint = fpsColor(fps), modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(6.dp))
            Text("${fps.roundToInt()}", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.width(4.dp))
            Text("FPS", color = Color.White.copy(alpha = 0.45f), fontSize = 9.sp, letterSpacing = 1.2.sp)
            Spacer(Modifier.weight(1f))
            Text("%.1f ms".format(frameMs), color = Color.White.copy(alpha = 0.55f), fontSize = 10.sp, fontFamily = FontFamily.Monospace)
            Spacer(Modifier.width(6.dp))
            EqsButton(showMath, onToggleMath)
        }
        Spacer(Modifier.height(6.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Tag(sim.preset.displayName.uppercase(), Tone.ACCENT)
            Tag("${(scale * 100).roundToInt()}%", if (scale < 0.95f) Tone.WARNING else Tone.NEUTRAL)
            if (sim.preset.taaEnabled) Tag("TAA", Tone.NEUTRAL)
            if (sim.preset.bloomEnabled) Tag("BLOOM", Tone.NEUTRAL)
        }
        Divider()
        Metric("rh", "%.2f M".format(rh))
        Metric("rph", "%.2f M".format(rph))
        Metric("ISCO", "%.2f M".format(isco))
        if (showMath) {
            Divider()
            MathPanel()
        }
    }
}

@Composable
private fun EqsButton(on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(if (on) Color(0x4D338CD9) else Color.White.copy(alpha = 0.06f))
            .border(BorderStroke(0.7.dp, if (on) Accent.copy(alpha = 0.55f) else Color.White.copy(alpha = 0.14f)), RoundedCornerShape(50))
            .clickable(onClickLabel = if (on) "Hide equations" else "Show equations") { onClick() }
            .padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Outlined.Functions, contentDescription = null, tint = if (on) Accent else Color.White.copy(alpha = 0.62f), modifier = Modifier.size(10.dp))
        Spacer(Modifier.width(3.dp))
        Text("EQS", color = if (on) Accent else Color.White.copy(alpha = 0.62f), fontSize = 9.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp)
    }
}

private enum class Tone { ACCENT, NEUTRAL, WARNING }

@Composable
private fun Tag(text: String, tone: Tone) {
    val (fg, bg, br) = when (tone) {
        Tone.ACCENT -> Triple(Accent, Color(0x4D338CD9), Accent.copy(alpha = 0.4f))
        Tone.NEUTRAL -> Triple(Color.White.copy(alpha = 0.78f), Color.White.copy(alpha = 0.06f), Color.White.copy(alpha = 0.15f))
        Tone.WARNING -> Triple(Amber, Color(0x33FF9919), Amber.copy(alpha = 0.45f))
    }
    Text(text, color = fg, fontSize = 8.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(bg)
            .border(BorderStroke(0.6.dp, br), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 2.dp))
}

@Composable
private fun Divider() {
    Spacer(Modifier.height(8.dp))
    Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.10f)))
    Spacer(Modifier.height(8.dp))
}

@Composable
private fun Metric(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 1.dp)) {
        Text(label, color = Color.White.copy(alpha = 0.5f), fontSize = 10.sp, fontFamily = FontFamily.Monospace)
        Spacer(Modifier.weight(1f))
        Text(value, color = Color.White.copy(alpha = 0.88f), fontSize = 11.sp, fontFamily = FontFamily.Monospace)
    }
}

private fun fpsColor(fps: Float): Color = when {
    fps < 30 -> Color(0xFFFF4D4D)
    fps < 50 -> Amber
    else -> Color(0xFF59F2A6)
}

/** Same equations and citations as the iOS math panel. */
@Composable
private fun MathPanel() {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        SectionLabel("Kerr geometry")
        Eq("Event horizon", "r₊ = M + √(M² − a²)", "Bardeen 1973")
        Eq("Photon sphere", "r_ph = 2M[1 + cos(⅔ arccos(−a*))]", "Bardeen 1973")
        Eq("ISCO", "r_ISCO = M[3 + Z₂ − √((3−Z₁)(3+Z₁+2Z₂))]", "Bardeen, Press & Teukolsky 1972")
        Eq("Ergosphere", "r_E(θ) = M + √(M² − a²cos²θ)", "Kerr 1963")
        SectionLabel("Geodesic dynamics")
        Eq("Kerr-Schild accel", "a = −(M/r² + 3M L²/r⁴)(σ/r²) r̂ + ω (ŷ × v)", "Chandrasekhar 1983")
        Eq("Frame dragging (ZAMO)", "ω = 2Ma / (r³ + a²r)", "Bardeen, Press & Teukolsky 1972")
        SectionLabel("Accretion disk")
        Eq("Keplerian Ω", "Ω = sgn(a*) √M / (r^(3/2) + a√M)", "Page & Thorne 1974")
        Eq("Doppler factor", "δ = 1 / [u_t (1 − Ω L_z)]", "Page & Thorne 1974")
        Eq("Novikov–Thorne T(r)", "T ∝ T₀ (r_ISCO/r)^(3/4) (1 − √(r_ISCO/r))^(1/4) δ", "Novikov & Thorne 1973")
        Eq("Relativistic beaming", "I_obs = I_em δ^(7/2)", "Liouville's theorem")
        SectionLabel("Pipeline")
        Eq("Blackbody (linear)", "c_lin = (Tanner-Helland(T))^2.2", "Tanner-Helland approx.")
        Eq("ACES tonemap", "c' = clamp(c(2.51c+0.03) / (c(2.43c+0.59)+0.14))", "Narkowicz 2014")
    }
}

@Composable
private fun Eq(title: String, formula: String, cite: String) {
    Column {
        Row {
            Text(title, color = Color.White.copy(alpha = 0.55f), fontSize = 10.sp, fontWeight = FontWeight.Medium)
            Spacer(Modifier.weight(1f))
            Text(cite, color = Color.White.copy(alpha = 0.30f), fontSize = 8.sp)
        }
        Text(formula, color = Color.White.copy(alpha = 0.92f), fontSize = 11.sp,
            fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic)
    }
}
