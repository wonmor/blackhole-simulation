package com.orchestrsim.blackhole.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.orchestrsim.blackhole.billing.ProManager
import com.orchestrsim.blackhole.model.Lesson

/** Lesson index (full-screen). */
@Composable
fun LessonsList(pro: ProManager, onPick: (Lesson) -> Unit, onClose: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFF05070A))
            .safeDrawingPadding()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text("Lessons", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(
                    "Eight short guided tours of the physics on screen. Each sets up the simulator, explains what you are seeing, and gives you something to try.",
                    color = Color.White.copy(alpha = 0.62f), fontSize = 12.sp
                )
            }
            IconButton(onClick = onClose) {
                Icon(Icons.Outlined.Close, contentDescription = "Close", tint = Color.White.copy(alpha = 0.7f))
            }
        }
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Lesson.entries.forEach { l ->
                val locked = l.isPro && !pro.isPro
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color.White.copy(alpha = 0.05f))
                        .clickable { if (locked) pro.openPaywall("Lesson ${l.number}") else onPick(l) }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("${l.number}. ${l.title}", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text(l.summary, color = Color.White.copy(alpha = 0.58f), fontSize = 12.sp)
                    }
                    if (locked) {
                        Text("PRO", color = Color.Black, fontSize = 9.sp, fontWeight = FontWeight.Bold,
                            modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(Accent).padding(horizontal = 5.dp, vertical = 2.dp))
                        Spacer(Modifier.width(8.dp))
                        Icon(Icons.Outlined.Lock, contentDescription = "Locked", tint = Color.White.copy(alpha = 0.5f), modifier = Modifier.size(16.dp))
                    } else {
                        Icon(Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = null, tint = Color.White.copy(alpha = 0.5f), modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
    }
}

/** Card over the live simulation while a lesson is active. */
@Composable
fun LessonCard(lesson: Lesson, pro: ProManager, onGo: (Lesson) -> Unit, onEnd: () -> Unit, modifier: Modifier = Modifier) {
    var expanded by remember(lesson) { mutableStateOf(true) }
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0xE6080A0E))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("LESSON ${lesson.number} OF ${Lesson.entries.size}", color = Accent, fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp, modifier = Modifier.weight(1f))
            IconButton(onClick = { expanded = !expanded }, modifier = Modifier.size(32.dp)) {
                Icon(if (expanded) Icons.Outlined.ExpandMore else Icons.Outlined.ExpandLess,
                    contentDescription = if (expanded) "Collapse" else "Expand", tint = Color.White.copy(alpha = 0.7f))
            }
            IconButton(onClick = onEnd, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Outlined.Close, contentDescription = "End lesson", tint = Color.White.copy(alpha = 0.7f))
            }
        }
        Text(lesson.title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        if (expanded) {
            Column(Modifier.heightIn(max = 180.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(lesson.body, color = Color.White.copy(alpha = 0.85f), fontSize = 12.sp)
                Text(lesson.tryThis, color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            val prev = Lesson.entries.getOrNull(lesson.ordinal - 1)
            if (prev != null) TextButton(onClick = { onGo(prev) }) { Text("Previous", color = Color.White) }
            Spacer(Modifier.weight(1f))
            val next = Lesson.entries.getOrNull(lesson.ordinal + 1)
            if (next == null) {
                TextButton(onClick = onEnd) { Text("Finish", color = Accent) }
            } else {
                val locked = next.isPro && !pro.isPro
                Button(
                    onClick = { if (locked) pro.openPaywall("Lesson ${next.number}") else onGo(next) },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (locked) Accent else Color.White.copy(alpha = 0.12f),
                        contentColor = if (locked) Color.Black else Color.White
                    ),
                    shape = RoundedCornerShape(9.dp)
                ) { Text(if (locked) "Next lesson with Pro" else "Next: ${next.title}", fontSize = 12.sp, maxLines = 1) }
            }
        }
    }
}
