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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.billing.ProManager

const val PRIVACY_URL = "https://wonmor.github.io/blackhole-simulation/privacy/"
const val TERMS_URL = "https://play.google.com/about/play-terms/"

/** Full-screen BlackHole Pro paywall. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Paywall(pro: ProManager, onClose: () -> Unit) {
    val ctx = LocalContext.current
    val plans = pro.plans()
    var selected by remember { mutableStateOf("lifetime") }
    val chosen = plans.firstOrNull { it.key == selected } ?: plans.firstOrNull()

    fun open(url: String) = ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF05070A))
            .safeDrawingPadding()
    ) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(
                        pro.paywallHeadline ?: pro.paywallReason?.let { "$it is part of Pro" } ?: "BlackHole Pro",
                        color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Mass, spin, the disk, Low to High quality, four scenarios, two lessons and snapshots stay free. Pro adds the rest, once, for good.",
                        color = Color.White.copy(alpha = 0.62f), fontSize = 12.sp
                    )
                }
                IconButton(onClick = onClose) {
                    Icon(Icons.Outlined.Close, contentDescription = "Close", tint = Color.White.copy(alpha = 0.7f))
                }
            }

            feature(Icons.Outlined.Camera, "Ultra and Cinematic ray tracing",
                "Up to 500 geodesic steps per pixel: a sharper photon ring and more higher-order images.")
            feature(Icons.Outlined.AutoAwesome, "Six more scenarios",
                "M87*, a film-style thin disk, retrograde spin, Cygnus X-1, a quasar and a bare shadow.")
            feature(Icons.Outlined.School, "All eight lessons",
                "Guided tours of Doppler beaming, redshift, frame dragging, the ISCO, disk colour and jets.")
            feature(Icons.Outlined.Tune, "Studio tuning",
                "Lensing and frame-drag strength, bloom and camera auto-spin.")
            feature(Icons.Outlined.FavoriteBorder, "Support an independent developer",
                "No ads, no tracking, no account. Pro is how the app is funded.")

            Text("CHOOSE A PLAN", color = Accent, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)

            if (plans.isEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (pro.loading) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text("Loading prices from Google Play…", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
                    } else {
                        Text("Prices could not be loaded.", color = Color.White.copy(alpha = 0.6f), fontSize = 12.sp)
                        TextButton(onClick = { pro.refresh() }) { Text("Try again", color = Accent) }
                    }
                }
            }
            plans.forEach { p ->
                val isSel = chosen?.key == p.key
                val badge = if (p.key == "lifetime") "BEST VALUE" else null
                val terms = when {
                    p.key == "lifetime" -> "One-time purchase. Pro forever, no subscription."
                    p.trialDays > 0 -> "${trialLabel(p.trialDays)} free, then ${p.price} ${p.per}"
                    else -> "${p.price} ${p.per}, auto-renews"
                }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (isSel) Accent.copy(alpha = 0.14f) else Color.White.copy(alpha = 0.04f))
                        .border(BorderStroke(if (isSel) 1.2.dp else 0.6.dp,
                            if (isSel) Accent.copy(alpha = 0.7f) else Color.White.copy(alpha = 0.12f)),
                            RoundedCornerShape(12.dp))
                        .clickable { selected = p.key }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Outlined.Check, contentDescription = null,
                        tint = if (isSel) Accent else Color.Transparent, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(p.title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                            badge?.let {
                                Text(it, color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Bold,
                                    modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Accent).padding(horizontal = 6.dp, vertical = 2.dp))
                            }
                        }
                        Text(terms, color = Color.White.copy(alpha = 0.62f), fontSize = 11.sp)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(p.price, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        Text(p.per, color = Color.White.copy(alpha = 0.5f), fontSize = 10.sp)
                    }
                }
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .background(Color.Black.copy(alpha = 0.6f))
                .padding(horizontal = 20.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Button(
                onClick = { chosen?.let { pro.buy(ctx as Activity, it) } ?: pro.refresh() },
                enabled = !pro.busy,
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Color.Black)
            ) {
                if (pro.busy) CircularProgressIndicator(Modifier.size(18.dp), color = Color.Black, strokeWidth = 2.dp)
                else Text(
                    when {
                        chosen == null -> "Continue"
                        chosen.key == "lifetime" -> "Unlock Pro for ${chosen.price}"
                        chosen.trialDays > 0 -> "Start free trial"
                        else -> "Subscribe for ${chosen.price}"
                    },
                    fontSize = 15.sp, fontWeight = FontWeight.SemiBold
                )
            }
            if (chosen != null) {
                Text(
                    when {
                        chosen.key == "lifetime" -> "Pay once. No renewals."
                        chosen.trialDays > 0 -> "${trialLabel(chosen.trialDays)} free, then ${chosen.price} ${chosen.per} until you cancel. Cancel before the trial ends and you won't be charged."
                        else -> "${chosen.price} ${chosen.per} until you cancel."
                    },
                    color = Color.White.copy(alpha = 0.6f), fontSize = 11.sp, textAlign = TextAlign.Center
                )
            }
            Text(
                "Lifetime is a single payment with no renewals. Yearly renews automatically at the same price until cancelled; cancel any time in Google Play, Payments and subscriptions.",
                color = Color.White.copy(alpha = 0.42f), fontSize = 10.sp, textAlign = TextAlign.Center
            )
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
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

    pro.message?.let { msg ->
        AlertDialog(
            onDismissRequest = { pro.message = null },
            confirmButton = { TextButton(onClick = { pro.message = null }) { Text("OK") } },
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

@Composable
private fun feature(icon: ImageVector, title: String, text: String) {
    Row(verticalAlignment = Alignment.Top) {
        Icon(icon, contentDescription = null, tint = Accent, modifier = Modifier.size(20.dp).padding(top = 1.dp))
        Spacer(Modifier.width(10.dp))
        Column {
            Text(title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Text(text, color = Color.White.copy(alpha = 0.66f), fontSize = 12.sp)
        }
    }
}
