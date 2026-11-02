package com.orchestrsim.blackhole.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.NativeBridge
import com.orchestrsim.blackhole.R

/** First-launch explainer, same copy as the iOS WelcomeSheet. */
@Composable
fun WelcomeContent(onLearnMore: () -> Unit, onStart: () -> Unit) {
    Column(
        Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            BrandMark(44)
            Spacer(Modifier.width(14.dp))
            Column {
                Text("BLACKHOLE", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.ExtraLight, letterSpacing = 5.sp)
                Text("A real-time general-relativity simulator, not a video loop.", color = Color.White.copy(alpha = 0.65f), fontSize = 12.sp)
            }
        }
        Text("Every frame traces light rays backwards through the curved spacetime of a spinning (Kerr) black hole on your GPU. Change the mass or spin and the shadow, lensing, and accretion disk are re-solved from the metric, live.",
            color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp)
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Point(Icons.Outlined.Tune, "Tune the physics",
                "Mass, spin a*, disk size, density, temperature, scale height and rotation speed. The HUD reports the event horizon, photon sphere and ISCO radii as you drag.")
            Point(Icons.Outlined.Functions, "See the equations",
                "Tap EQS in the HUD to list every closed-form equation the shader evaluates, with its literature citation (Bardeen, Page–Thorne, Novikov–Thorne).")
            Point(Icons.Outlined.AutoAwesome, "Load a scenario",
                "One tap jumps to a stellar-mass hole, a Sgr A* proxy, a near-extremal Kerr hole, or a non-rotating Schwarzschild hole.")
            Point(Icons.Outlined.School, "Take a lesson",
                "Short guided tours set up the simulator and explain the shadow, lensing, Doppler beaming and more.")
            Point(Icons.Outlined.PanTool, "Explore",
                "Drag to orbit, pinch to zoom from the photon ring out past the disk.")
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = onLearnMore, shape = RoundedCornerShape(50),
                border = BorderStroke(0.6.dp, Color.White.copy(alpha = 0.18f))) {
                Text("Learn more", color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
            }
            Spacer(Modifier.weight(1f))
            Button(onClick = onStart, shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.Black)) {
                Text("Start exploring", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
fun BrandMark(size: Int) {
    Image(painterResource(R.drawable.brand_mark), contentDescription = null,
        modifier = Modifier.size(size.dp).clip(RoundedCornerShape((size * 0.23f).dp)))
}

@Composable
private fun Point(icon: ImageVector, title: String, body: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = Accent, modifier = Modifier.size(18.dp).padding(top = 1.dp))
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text(body, color = Color.White.copy(alpha = 0.62f), fontSize = 12.sp)
        }
    }
}

const val SUPPORT_URL = "https://github.com/wonmor/blackhole-simulation"
const val PHYSICS_URL = "https://github.com/wonmor/blackhole-simulation/blob/main/docs/PHYSICS.md"

/** About BlackHole, ported from the iOS AboutSheet. */
@Composable
fun AboutContent(versionName: String, versionCode: Long, onClose: () -> Unit) {
    val ctx = LocalContext.current
    fun open(u: String) = runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u))) }
    val engine = runCatching { "gravitas ${NativeBridge.nativeGravitasVersion()} (Rust)" }.getOrDefault("gravitas (Rust)")
    Column(
        Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            BrandMark(42)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("BLACKHOLE", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.ExtraLight, letterSpacing = 5.sp)
                Text("Real-time Kerr black hole simulator", color = Color.White.copy(alpha = 0.55f), fontSize = 11.sp)
            }
            CloseButton(onClose)
        }
        Rule()
        SectionLabel("What it computes")
        Text("BlackHole integrates null geodesics through the Kerr–Schild metric in a Vulkan fragment shader, so every pixel of every frame is a light ray traced through the curved spacetime of a rotating black hole on your GPU. Nothing is pre-rendered: change the mass or spin and the shadow, gravitational lensing, frame-dragging and the Page–Thorne accretion disk (Doppler boost, Novikov–Thorne temperature profile, blackbody colour) are recomputed live.",
            color = Color.White.copy(alpha = 0.80f), fontSize = 12.sp)
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Dash("Live readouts of the event horizon, photon sphere and ISCO radii for the current mass and spin (Bardeen 1973; Bardeen, Press & Teukolsky 1972).")
            Dash("An equations panel (EQS in the HUD) listing each closed-form expression the renderer evaluates, with its citation.")
            Dash("Scenarios: stellar-mass, Sgr A* proxy, near-extremal Kerr and non-rotating Schwarzschild, plus six more with Pro.")
            Dash("Quality presets that trade ray-marching steps, render scale, temporal AA and bloom for frame rate.")
        }
        Rule()
        Row2("VERSION", "$versionName ($versionCode)")
        Row2("RENDERER", "Vulkan 1.1 | GLSL fragment shader")
        Row2("PHYSICS", "Kerr-Schild geodesic | Page-Thorne disk")
        Row2("KERR ENGINE", engine)
        Rule()
        SectionLabel("Credits")
        Text("Developed by John Seong at Orch Aerospace, Inc.", color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
        Text("Based in part on open-source work by Mayank Pratap Singh (MIT License)", color = Color.White.copy(alpha = 0.55f), fontSize = 11.sp)
        Rule()
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("Support") { open(SUPPORT_URL) }
            Pill("Physics notes") { open(PHYSICS_URL) }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("Privacy Policy") { open(PRIVACY_URL) }
            Pill("Terms of Service") { open(TERMS_URL) }
        }
        Spacer(Modifier.height(10.dp))
    }
}

@Composable private fun Rule() = Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.10f)))

@Composable
private fun Dash(text: String) {
    Row {
        Text("–", color = Accent.copy(alpha = 0.8f), fontSize = 11.sp)
        Spacer(Modifier.width(8.dp))
        Text(text, color = Color.White.copy(alpha = 0.70f), fontSize = 11.sp)
    }
}

@Composable
private fun Row2(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Color.White.copy(alpha = 0.5f), fontSize = 9.sp, fontFamily = FontFamily.Monospace, letterSpacing = 1.sp)
        Spacer(Modifier.width(12.dp))
        Spacer(Modifier.weight(1f))
        Text(value, color = Color.White.copy(alpha = 0.88f), fontSize = 11.sp, fontFamily = FontFamily.Monospace)
    }
}

@Composable
private fun Pill(text: String, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(50), color = Color.White.copy(alpha = 0.06f),
        border = BorderStroke(0.6.dp, Color.White.copy(alpha = 0.18f))) {
        Text(text.uppercase(), color = Color.White.copy(alpha = 0.75f), fontSize = 9.sp, fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.5.sp, modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp))
    }
}
