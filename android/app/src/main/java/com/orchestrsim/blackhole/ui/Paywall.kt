package com.orchestrsim.blackhole.ui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.billing.ProManager
import java.text.DateFormat
import java.util.Date

const val PRIVACY_URL = "https://wonmor.github.io/blackhole-simulation/privacy/"
const val TERMS_URL = "https://play.google.com/about/play-terms/"

/**
 * Full-screen BlackHole Pro paywall. It is transparent at the top so the live
 * simulation keeps rendering behind it. The close glyph is always visible;
 * prices and terms come from Google Play (trial, intro year and launch sale
 * included) and are spelled out next to the button. No fake social proof:
 * the app has too few Play ratings to quote honestly, so it says what is true
 * instead (no ads, no tracking, no account).
 */
@Composable
fun Paywall(pro: ProManager, onClose: () -> Unit) {
    val ctx = LocalContext.current
    val tick = rememberTick()
    val plans = pro.plans()
    var selected by remember { mutableStateOf("lifetime") }
    val chosen = plans.firstOrNull { it.key == selected } ?: plans.firstOrNull()
    val screenH = LocalConfiguration.current.screenHeightDp

    fun open(url: String) = runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }

    Box(
        Modifier.fillMaxSize().background(
            Brush.verticalGradient(
                0f to Color.Transparent, 0.30f to Color(0x22000000), 0.40f to Color(0xCC05070A),
                0.48f to Color(0xF705070A), 1f to Color(0xFF05070A)
            )
        ).clickable(enabled = false) { }
    ) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onClose,
                    colors = IconButtonDefaults.iconButtonColors(containerColor = Color.Black.copy(alpha = 0.45f))) {
                    Icon(Icons.Outlined.Close, contentDescription = "Close", tint = Color.White.copy(alpha = 0.85f))
                }
            }
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 22.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Let the render breathe at the top on tall screens.
                Spacer(Modifier.height((screenH * 0.26f).coerceIn(40f, 260f).dp))
                Text("BLACKHOLE PRO", color = Accent, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 3.sp)
                Text(
                    pro.paywallHeadline ?: pro.paywallReason?.let { "$it is part of Pro" } ?: "Unlock the whole universe",
                    color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold, lineHeight = 32.sp
                )
                Text(
                    "The simulator, mass, spin, the disk, Low to High quality, four scenarios, two lessons and screen saves stay free. Pro adds the rest.",
                    color = Color.White.copy(alpha = 0.66f), fontSize = 13.sp
                )
                Spacer(Modifier.height(2.dp))
                Value(Icons.Outlined.Wallpaper, "Live wallpaper", "The black hole, animated on your home screen.")
                Value(Icons.Outlined.Image, "4K poster and orbit video", "3840 px supersampled stills and 1080p 360° fly-arounds.")
                Value(Icons.Outlined.Camera, "Ultra and Cinematic ray tracing", "Up to 500 geodesic steps per pixel: a sharper photon ring.")
                Value(Icons.Outlined.AutoAwesome, "Six more scenarios", "M87*, Film look, retrograde spin, Cygnus X-1, a quasar, a bare shadow.")
                Value(Icons.Outlined.School, "All eight lessons", "Doppler beaming, redshift, frame dragging, the ISCO, disk colour, jets.")
                Value(Icons.Outlined.Timer, "Focus timer", "Pomodoro sessions over the simulation.")
                Value(Icons.Outlined.Tune, "Studio tuning", "Lensing, frame drag, bloom and camera auto-spin.")
                Value(Icons.Outlined.FavoriteBorder, "No ads, no tracking, no account", "Pro is how an independent developer funds the app.")

                Spacer(Modifier.height(4.dp))
                SectionLabel("Choose a plan")
                if (plans.isEmpty()) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (pro.loading) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Accent)
                            Text("Loading prices from Google Play…", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
                        } else {
                            Text("Prices could not be loaded.", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
                            TextButton(onClick = { pro.refresh() }) { Text("Try again", color = Accent) }
                        }
                    }
                }
                plans.forEach { p -> PlanRow(p, chosen?.key == p.key) { tick(); selected = p.key } }
                Spacer(Modifier.height(6.dp))
            }

            // Footer: CTA + terms + links
            Column(
                Modifier.fillMaxWidth().background(Color(0xFF05070A)).padding(horizontal = 20.dp, vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Button(
                    onClick = { chosen?.let { pro.buy(ctx as Activity, it) } ?: pro.refresh() },
                    enabled = !pro.busy,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.Black)
                ) {
                    if (pro.busy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.Black, strokeWidth = 2.dp)
                    else Text(ctaTitle(chosen), fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
                if (chosen != null) {
                    Text(finePrint(chosen), color = Color.White.copy(alpha = 0.62f), fontSize = 11.sp, textAlign = TextAlign.Center)
                }
                Text(
                    "Lifetime is a single payment with no renewals. Yearly renews automatically until cancelled; cancel any time in Google Play, Payments and subscriptions.",
                    color = Color.White.copy(alpha = 0.40f), fontSize = 10.sp, textAlign = TextAlign.Center
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { pro.restore() }, enabled = !pro.busy) { Text("Restore", color = Accent, fontSize = 12.sp) }
                    Text("|", color = Color.White.copy(alpha = 0.25f))
                    TextButton(onClick = { open("https://play.google.com/store/account/subscriptions?package=${ctx.packageName}") }) {
                        Text("Manage", color = Accent, fontSize = 12.sp)
                    }
                    Text("|", color = Color.White.copy(alpha = 0.25f))
                    TextButton(onClick = { open(TERMS_URL) }) { Text("Terms", color = Accent, fontSize = 12.sp) }
                    Text("|", color = Color.White.copy(alpha = 0.25f))
                    TextButton(onClick = { open(PRIVACY_URL) }) { Text("Privacy", color = Accent, fontSize = 12.sp) }
                }
            }
        }
    }

    pro.message?.let { msg ->
        AlertDialog(
            onDismissRequest = { pro.message = null },
            confirmButton = { TextButton(onClick = { pro.message = null }) { Text("OK", color = Accent) } },
            text = { Text(msg) }
        )
    }
}

private fun trialLabel(days: Int): String = when {
    days % 7 == 0 && days / 7 == 1 -> "1 week"
    days % 7 == 0 -> "${days / 7} weeks"
    days == 1 -> "1 day"
    else -> "$days days"
}

private fun ctaTitle(p: ProManager.Plan?): String = when {
    p == null -> "Continue"
    p.key == "lifetime" -> "Unlock Pro for ${p.price}"
    p.trialDays > 0 -> "Start ${trialLabel(p.trialDays)} free trial"
    p.introPrice != null -> "Get Pro for ${p.introPrice}"
    else -> "Subscribe for ${p.price}"
}

private fun finePrint(p: ProManager.Plan): String = when {
    p.key == "lifetime" -> "Pay once. Pro forever, no renewals."
    p.trialDays > 0 -> "${(p.terms ?: "${trialLabel(p.trialDays)} free, then ${p.price} per year").replaceFirstChar { it.uppercase() }}, until you cancel. Cancel before the trial ends and you won't be charged."
    else -> "${(p.terms ?: "${p.price} per year").replaceFirstChar { it.uppercase() }}, until you cancel."
}

@Composable
private fun Value(icon: ImageVector, title: String, text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = Accent, modifier = Modifier.size(20.dp).padding(top = 1.dp))
        Spacer(Modifier.width(12.dp))
        Column {
            Text(title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(text, color = Color.White.copy(alpha = 0.64f), fontSize = 12.sp)
        }
    }
}

@Composable
private fun PlanRow(p: ProManager.Plan, isSel: Boolean, onClick: () -> Unit) {
    val badge: Pair<String, Color>? = when {
        p.key == "lifetime" && p.percentOff != null -> "LAUNCH SALE  ${p.percentOff}% OFF" to Amber
        p.key == "lifetime" -> "BEST VALUE" to Accent
        p.trialDays > 0 -> "${trialLabel(p.trialDays).uppercase()} FREE" to Accent
        p.winback -> "WELCOME BACK" to Accent
        p.introPrice != null -> "FIRST YEAR ${p.introPrice}" to Accent
        else -> null
    }
    val sub = when {
        p.key == "lifetime" -> buildString {
            append("One payment. Pro forever, no subscription.")
            p.saleEndsMillis?.let { append(" Sale ends ${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(it - 1))}.") }
        }
        else -> listOfNotNull(p.terms?.replaceFirstChar { it.uppercase() }, p.perMonth).joinToString(" | ")
    }
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(if (isSel) Accent.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.04f))
            .border(BorderStroke(if (isSel) 1.4.dp else 0.6.dp, if (isSel) Accent.copy(alpha = 0.8f) else Color.White.copy(alpha = 0.14f)),
                RoundedCornerShape(14.dp))
            .clickable { onClick() }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Outlined.Check, contentDescription = null,
            tint = if (isSel) Accent else Color.Transparent, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(p.title, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                badge?.let { (t, c) ->
                    Text(t, color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp,
                        modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(c).padding(horizontal = 6.dp, vertical = 2.dp))
                }
            }
            Text(sub, color = Color.White.copy(alpha = 0.62f), fontSize = 11.sp)
        }
        Spacer(Modifier.width(8.dp))
        Column(horizontalAlignment = Alignment.End) {
            p.fullPrice?.let {
                Text(it, color = Color.White.copy(alpha = 0.45f), fontSize = 11.sp, textDecoration = TextDecoration.LineThrough)
            }
            val headline = if (p.key != "lifetime" && p.trialDays == 0 && p.introPrice != null) p.introPrice else p.price
            Text(headline, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            Text(p.per, color = Color.White.copy(alpha = 0.5f), fontSize = 10.sp)
        }
    }
}
