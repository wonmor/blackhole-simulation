package com.orchestrsim.blackhole.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.billing.ProManager
import com.orchestrsim.blackhole.export.ExportStudio

/** Save and export: the screen frame is free; the 4K poster, the orbit video
 *  and the live wallpaper are Pro. Same options as the iOS ExportSheet, plus
 *  the Android-only live wallpaper. */
@Composable
fun ExportContent(
    pro: ProManager,
    onClose: () -> Unit,
    onSaveFrame: () -> Unit,
    onPoster: () -> Unit,
    onVideo: () -> Unit,
    onWallpaper: () -> Unit
) {
    val st = ExportStudio.state
    val busy = ExportStudio.isBusy
    val locked = !pro.isPro
    Column(Modifier.padding(horizontal = 22.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SheetHeader("Save and export",
            "Exports render offscreen at a fixed resolution with the current settings and camera.",
            onClose, closeEnabled = !busy)
        OptionRow(Icons.Outlined.Download, "Save screen frame", "What's on screen now, at screen resolution. Free.",
            locked = false, enabled = !busy, trailing = Icons.AutoMirrored.Outlined.KeyboardArrowRight) { onSaveFrame() }
        OptionRow(Icons.Outlined.Image, "4K poster", "3840 px, 500 ray steps, 16-pass supersampling.",
            locked = locked, enabled = !busy, trailing = Icons.AutoMirrored.Outlined.KeyboardArrowRight) {
            if (locked) pro.openPaywall("The 4K poster") else onPoster()
        }
        OptionRow(Icons.Outlined.Movie, "Orbit video", "12 s, 1080p, 30 fps, a full 360° fly-around.",
            locked = locked, enabled = !busy, trailing = Icons.AutoMirrored.Outlined.KeyboardArrowRight) {
            if (locked) pro.openPaywall("Orbit video") else onVideo()
        }
        OptionRow(Icons.Outlined.Wallpaper, "Live wallpaper", "The black hole, animated on your home screen, in the look you set here.",
            locked = locked, enabled = !busy, trailing = Icons.AutoMirrored.Outlined.KeyboardArrowRight) {
            if (locked) pro.openPaywall("The live wallpaper") else onWallpaper()
        }
        when (st) {
            is ExportStudio.State.Rendering -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(st.label, color = Color.White.copy(alpha = 0.8f), fontSize = 12.sp, fontWeight = FontWeight.Medium)
                LinearProgressIndicator(progress = { st.progress }, modifier = Modifier.fillMaxWidth(), color = Accent)
                TextButton(onClick = { ExportStudio.cancel() }) { Text("Cancel", color = Accent, fontSize = 12.sp) }
            }
            ExportStudio.State.Saving -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Accent)
                Spacer(Modifier.width(8.dp))
                Text("Saving…", color = Color.White.copy(alpha = 0.8f), fontSize = 12.sp)
            }
            is ExportStudio.State.Done -> Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Check, contentDescription = null, tint = Accent, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(st.message, color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
            is ExportStudio.State.Failed -> Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = Amber, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(st.message, color = Amber, fontSize = 12.sp)
            }
            ExportStudio.State.Idle -> Unit
        }
        Spacer(Modifier.height(12.dp))
    }
}
