package com.orchestrsim.blackhole

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape as Rcs
import com.orchestrsim.blackhole.model.SimState
import com.orchestrsim.blackhole.ui.BlackHoleTheme
import com.orchestrsim.blackhole.ui.ControlPanel
import com.orchestrsim.blackhole.ui.Hud
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged

class MainActivity : ComponentActivity() {
    private lateinit var sim: SimState

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        sim = SimState(this)
        setContent { BlackHoleTheme { BlackHoleApp(sim) } }
    }

    override fun onPause() {
        super.onPause()
        NativeBridge.nativeOnPause(true)
    }

    override fun onResume() {
        super.onResume()
        NativeBridge.nativeOnPause(false)
    }
}

@Composable
private fun BlackHoleApp(sim: SimState) {
    var showControls by remember { mutableStateOf(false) }
    var fps by remember { mutableStateOf(0f) }
    var scale by remember { mutableStateOf(1f) }

    // Native Vulkan surface behind everything.
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx -> BlackHoleSurfaceView(ctx, sim) },
            modifier = Modifier.fillMaxSize()
        )

        // Push the full param block whenever any tracked value changes.
        LaunchedEffect(Unit) {
            snapshotFlow { paramSnapshot(sim) }
                .distinctUntilChanged()
                .collect { sim.pushParams() }
        }

        // Poll telemetry for the HUD.
        LaunchedEffect(Unit) {
            val out = FloatArray(3)
            while (true) {
                NativeBridge.nativeGetTelemetry(out)
                fps = out[0]; scale = out[2]
                delay(250)
            }
        }

        Hud(
            sim, fps, scale,
            modifier = Modifier
                .align(Alignment.TopStart)
                .safeDrawingPadding()
                .padding(12.dp)
        )

        FilledIconButton(
            onClick = { showControls = !showControls },
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = Color.Black.copy(alpha = 0.55f),
                contentColor = Color.White
            ),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .safeDrawingPadding()
                .padding(12.dp)
        ) { Icon(Icons.Filled.Tune, contentDescription = "Controls") }

        AnimatedVisibility(
            visible = showControls,
            enter = slideInVertically { it },
            exit = slideOutVertically { it },
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.6f)
                    .clip(Rcs(topStart = 20.dp, topEnd = 20.dp))
                    .background(Color(0xFF0B0D11).copy(alpha = 0.96f))
                    .safeDrawingPadding()
            ) { ControlPanel(sim) }
        }

        // Bottom credit — mirrors the iOS FooterView. Low opacity, centered,
        // and not hit-testable so it never intercepts camera drags.
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .safeDrawingPadding()
                .padding(bottom = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                "DEVELOPED BY JOHN SEONG AT ORCH AEROSPACE, INC.",
                color = Color.White.copy(alpha = 0.55f),
                fontSize = 9.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 2.sp,
                textAlign = TextAlign.Center
            )
            Text(
                "Fork of project by Mayank Pratap Singh",
                color = Color.White.copy(alpha = 0.30f),
                fontSize = 9.sp,
                textAlign = TextAlign.Center
            )
        }
    }
}

// A value whose identity changes when any tracked parameter changes.
private fun paramSnapshot(s: SimState): List<Any> = listOf(
    s.mass, s.spin, s.lensingStrength, s.frameDragStrength,
    s.diskDensity, s.diskTemp, s.diskSize, s.diskScaleHeight,
    s.bloomThreshold, s.bloomIntensity, s.autoSpin,
    s.preset, s.enableLensing, s.enableDisk, s.enableDoppler,
    s.enablePhotonGlow, s.enableStars, s.enableJets, s.showRedshift
)
