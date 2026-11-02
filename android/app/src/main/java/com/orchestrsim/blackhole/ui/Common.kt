package com.orchestrsim.blackhole.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Shared visual language, matching the iOS panels: dark glass, a faint
 *  white-gradient edge, cyan accent for headers and active states. */
val PanelFill = Color(0xE60B0D11)
val SheetFill = Color(0xFF07090C)
val Amber = Color(0xFFFFC733)
val Violet = Color(0xFFA68CFF)

fun Modifier.glassPanel(radius: Dp = 14.dp): Modifier = this
    .clip(RoundedCornerShape(radius))
    .background(PanelFill)
    .border(
        BorderStroke(0.8.dp, Brush.linearGradient(listOf(Color.White.copy(alpha = 0.20f), Color.White.copy(alpha = 0.04f)))),
        RoundedCornerShape(radius)
    )

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier, color: Color = Accent.copy(alpha = 0.85f)) {
    Text(text.uppercase(), color = color, fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
        letterSpacing = 1.4.sp, modifier = modifier)
}

@Composable
fun ProBadge() {
    Row(
        Modifier.clip(RoundedCornerShape(4.dp)).background(Accent).padding(horizontal = 5.dp, vertical = 1.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Icon(Icons.Outlined.Lock, contentDescription = null, tint = Color.Black, modifier = Modifier.size(9.dp))
        Text("Pro", color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun CloseButton(onClick: () -> Unit, enabled: Boolean = true) {
    IconButton(onClick = onClick, enabled = enabled) {
        Icon(Icons.Outlined.Close, contentDescription = "Close", tint = Color.White.copy(alpha = 0.7f))
    }
}

/** Header row used by every sheet: title, optional subtitle, close glyph. */
@Composable
fun SheetHeader(title: String, subtitle: String?, onClose: () -> Unit, closeEnabled: Boolean = true) {
    Row(verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            if (subtitle != null) {
                Spacer(Modifier.height(4.dp))
                Text(subtitle, color = Color.White.copy(alpha = 0.62f), fontSize = 12.sp)
            }
        }
        CloseButton(onClose, closeEnabled)
    }
}

/** A tappable option row with a leading glyph (export, tools). */
@Composable
fun OptionRow(
    icon: ImageVector, title: String, sub: String, locked: Boolean,
    enabled: Boolean = true, trailing: ImageVector? = null, onClick: () -> Unit
) {
    val haptics = LocalHapticFeedback.current
    Surface(
        onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); onClick() },
        enabled = enabled,
        shape = RoundedCornerShape(12.dp),
        color = Color.White.copy(alpha = 0.05f),
        border = BorderStroke(0.6.dp, Color.White.copy(alpha = 0.12f)),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = Accent, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(title, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    if (locked) ProBadge()
                }
                Text(sub, color = Color.White.copy(alpha = 0.6f), fontSize = 11.sp)
            }
            val t = if (locked) Icons.Outlined.Lock else trailing
            if (t != null) Icon(t, contentDescription = null, tint = Color.White.copy(alpha = 0.45f), modifier = Modifier.size(16.dp))
        }
    }
}

/** Haptic tick used on selections (scenarios, presets, plans). */
@Composable
fun rememberTick(): () -> Unit {
    val h = LocalHapticFeedback.current
    return { h.performHapticFeedback(HapticFeedbackType.TextHandleMove) }
}
