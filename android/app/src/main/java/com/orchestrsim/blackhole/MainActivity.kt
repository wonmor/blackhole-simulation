package com.orchestrsim.blackhole

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.PixelCopy
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.*
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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.compose.foundation.shape.RoundedCornerShape as Rcs
import com.orchestrsim.blackhole.billing.Engagement
import com.orchestrsim.blackhole.billing.ProManager
import com.google.android.play.core.review.ReviewManagerFactory
import com.orchestrsim.blackhole.model.Lesson
import com.orchestrsim.blackhole.model.QualityPreset
import com.orchestrsim.blackhole.model.SimState
import com.orchestrsim.blackhole.ui.Accent
import com.orchestrsim.blackhole.ui.BlackHoleTheme
import com.orchestrsim.blackhole.ui.ControlPanel
import com.orchestrsim.blackhole.ui.Hud
import com.orchestrsim.blackhole.ui.LessonCard
import com.orchestrsim.blackhole.ui.LessonsList
import com.orchestrsim.blackhole.ui.Paywall
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged

class MainActivity : ComponentActivity() {
    private lateinit var sim: SimState
    private lateinit var pro: ProManager
    private lateinit var engagement: Engagement
    var surfaceView: BlackHoleSurfaceView? = null
    /** Debuggable builds only (`--ez debug_no_render true`): skip the Vulkan view so
     *  emulators without a usable GPU can still capture the Compose UI. */
    var skipRenderer = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Always light bar icons: the canvas is black in both system modes.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        sim = SimState(this)
        pro = ProManager(this)
        engagement = Engagement(this)
        applyDebugProOverride(intent)
        pro.start()
        setContent { BlackHoleTheme { BlackHoleApp(this, sim, pro) } }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        applyDebugProOverride(intent)
    }

    /**
     * Debuggable builds only: `adb shell am start -n <pkg>/com.orchestrsim.blackhole.MainActivity
     * --ez debug_pro true|false` forces the Pro state for testing and screenshots.
     * Ignored in release builds.
     */
    private fun applyDebugProOverride(intent: android.content.Intent?) {
        val debuggable = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (debuggable && intent?.getBooleanExtra("debug_no_render", false) == true) skipRenderer = true
        if (debuggable && intent?.hasExtra("debug_pro") == true) {
            pro.setDebugOverride(intent.getBooleanExtra("debug_pro", false))
        }
    }

    override fun onPause() {
        super.onPause()
        NativeBridge.nativeOnPause(true)
    }

    override fun onResume() {
        super.onResume()
        NativeBridge.nativeOnPause(false)
        pro.start()
    }

    override fun onDestroy() {
        pro.end()
        super.onDestroy()
    }

    /**
     * A good moment just happened (scenario applied, lesson finished, snapshot
     * saved). Shows the one-time paywall or asks for a Play rating, after a
     * short pause so the user first sees the result of what they did.
     */
    fun onMoment(m: Engagement.Moment) {
        when (engagement.onMoment(m, pro.isPro)) {
            Engagement.Action.PAYWALL -> Handler(Looper.getMainLooper()).postDelayed({
                if (!pro.isPro && !pro.showPaywall) pro.openPaywallAfterWow()
            }, 1500)
            Engagement.Action.REVIEW -> Handler(Looper.getMainLooper()).postDelayed({ askForReview() }, 1200)
            Engagement.Action.NONE -> Unit
        }
    }

    /** Play In-App Review. Play decides whether the sheet actually appears. */
    private fun askForReview() {
        if (isFinishing || isDestroyed) return
        val manager = ReviewManagerFactory.create(this)
        manager.requestReviewFlow().addOnCompleteListener { task ->
            if (task.isSuccessful && !isFinishing) manager.launchReviewFlow(this, task.result)
        }
    }

    /** Free: copies the current frame of the Vulkan surface into Pictures/BlackHole. */
    fun saveSnapshot() {
        val v = surfaceView ?: return
        if (v.width == 0 || v.height == 0) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 7)
            return
        }
        val bmp = Bitmap.createBitmap(v.width, v.height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(v, bmp, { result ->
            if (result != PixelCopy.SUCCESS) {
                Toast.makeText(this, "Couldn't capture the frame.", Toast.LENGTH_SHORT).show()
                return@request
            }
            val ok = runCatching {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, "BlackHole-${System.currentTimeMillis()}.png")
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/BlackHole")
                    }
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)!!
                contentResolver.openOutputStream(uri)!!.use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }.isSuccess
            Toast.makeText(this, if (ok) "Saved to Pictures/BlackHole" else "Couldn't save the image.", Toast.LENGTH_SHORT).show()
            if (ok) onMoment(Engagement.Moment.SNAPSHOT)
        }, Handler(Looper.getMainLooper()))
    }
}

@Composable
private fun BlackHoleApp(activity: MainActivity, sim: SimState, pro: ProManager) {
    var showControls by remember { mutableStateOf(false) }
    var showLessons by remember { mutableStateOf(false) }
    var activeLesson by remember { mutableStateOf<Lesson?>(null) }
    var fps by remember { mutableStateOf(0f) }
    var scale by remember { mutableStateOf(1f) }

    // Pro lapsed (refund / expiry): fall back to the best free preset.
    LaunchedEffect(pro.isPro) {
        if (!pro.isPro && sim.preset.isPro) sim.selectPreset(QualityPreset.HIGH)
    }

    BackHandler(enabled = pro.showPaywall || showLessons || showControls || activeLesson != null) {
        when {
            pro.showPaywall -> pro.showPaywall = false
            showLessons -> showLessons = false
            showControls -> showControls = false
            else -> activeLesson = null
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (!activity.skipRenderer) AndroidView(
            factory = { ctx -> BlackHoleSurfaceView(ctx, sim).also { activity.surfaceView = it } },
            modifier = Modifier.fillMaxSize()
        )

        LaunchedEffect(Unit) {
            snapshotFlow { paramSnapshot(sim) }
                .distinctUntilChanged()
                .collect { sim.pushParams() }
        }

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

        Row(
            Modifier
                .align(Alignment.TopEnd)
                .safeDrawingPadding()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            roundButton(Icons.Outlined.PhotoCamera, "Save snapshot") { activity.saveSnapshot() }
            roundButton(Icons.Outlined.Tune, "Controls") { showControls = !showControls }
        }

        // Bottom: lesson card, or Lessons / Pro entry points + credit.
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .safeDrawingPadding()
                .padding(horizontal = 12.dp)
                .padding(bottom = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            val lesson = activeLesson
            if (lesson != null) {
                LessonCard(lesson, pro,
                    onGo = { l ->
                        if (l.ordinal > lesson.ordinal) activity.onMoment(Engagement.Moment.LESSON_DONE)
                        sim.applyLesson(l, pro.isPro); activeLesson = l
                    },
                    onEnd = { activeLesson = null },
                    onFinish = { activeLesson = null; activity.onMoment(Engagement.Moment.LESSON_DONE) })
            } else if (!showControls) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    pill(Icons.Outlined.School, "Lessons", false) { showLessons = true }
                    if (!pro.isPro) {
                        val trial = pro.plans().any { it.trialDays > 0 }
                        pill(Icons.Outlined.AutoAwesome, if (trial) "Try Pro free" else "Get Pro", true) { pro.openPaywall() }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "DEVELOPED BY JOHN SEONG AT ORCH AEROSPACE, INC.",
                color = Color.White.copy(alpha = 0.55f), fontSize = 9.sp,
                fontWeight = FontWeight.SemiBold, letterSpacing = 2.sp, textAlign = TextAlign.Center
            )
            Text(
                "Fork of project by Mayank Pratap Singh",
                color = Color.White.copy(alpha = 0.30f), fontSize = 9.sp, textAlign = TextAlign.Center
            )
        }

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
                    .background(Color(0xFF0B0D11))
                    .navigationBarsPadding()
            ) {
                ControlPanel(sim, pro,
                    onLessons = { showControls = false; showLessons = true },
                    onSnapshot = { activity.saveSnapshot() },
                    onScenario = { s ->
                        sim.applyScenario(s, pro.isPro)
                        activity.onMoment(Engagement.Moment.SCENARIO)
                    })
            }
        }

        AnimatedVisibility(visible = showLessons, enter = fadeIn(), exit = fadeOut()) {
            LessonsList(pro,
                onPick = { l -> sim.applyLesson(l, pro.isPro); activeLesson = l; showLessons = false },
                onClose = { showLessons = false })
        }

        AnimatedVisibility(visible = pro.showPaywall, enter = fadeIn(), exit = fadeOut()) {
            Paywall(pro, onClose = { pro.showPaywall = false })
        }
    }
}

@Composable
private fun roundButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    FilledIconButton(
        onClick = onClick,
        colors = IconButtonDefaults.filledIconButtonColors(
            containerColor = Color.Black.copy(alpha = 0.55f),
            contentColor = Color.White
        )
    ) { Icon(icon, contentDescription = label) }
}

@Composable
private fun pill(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, accent: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        shape = Rcs(10.dp),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (accent) Accent else Color.Black.copy(alpha = 0.55f),
            contentColor = if (accent) Color.Black else Color.White
        )
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(6.dp))
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

// A value whose identity changes when any tracked parameter changes.
private fun paramSnapshot(s: SimState): List<Any> = listOf(
    s.mass, s.spin, s.lensingStrength, s.frameDragStrength, s.diskSpeed,
    s.diskDensity, s.diskTemp, s.diskSize, s.diskScaleHeight,
    s.bloomThreshold, s.bloomIntensity, s.autoSpin,
    s.preset, s.enableLensing, s.enableDisk, s.enableDoppler,
    s.enablePhotonGlow, s.enableStars, s.enableJets, s.showRedshift
)
