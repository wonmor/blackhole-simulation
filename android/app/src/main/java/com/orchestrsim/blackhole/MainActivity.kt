package com.orchestrsim.blackhole

import android.Manifest
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.School
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.play.core.review.ReviewManagerFactory
import com.orchestrsim.blackhole.billing.Engagement
import com.orchestrsim.blackhole.billing.ProManager
import com.orchestrsim.blackhole.export.ExportStudio
import com.orchestrsim.blackhole.export.MediaSaver
import com.orchestrsim.blackhole.focus.FocusTimer
import com.orchestrsim.blackhole.model.Lesson
import com.orchestrsim.blackhole.model.QualityPreset
import com.orchestrsim.blackhole.model.Scenario
import com.orchestrsim.blackhole.model.SimState
import com.orchestrsim.blackhole.ui.*
import com.orchestrsim.blackhole.wallpaper.BlackHoleWallpaperService
import com.orchestrsim.blackhole.wallpaper.WallpaperParams
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    lateinit var sim: SimState; private set
    lateinit var pro: ProManager; private set
    lateinit var focus: FocusTimer; private set
    private lateinit var engagement: Engagement
    var surfaceView: BlackHoleSurfaceView? = null
    /** Debuggable builds only (`--ez debug_no_render true`): skip the Vulkan view so
     *  emulators without a usable GPU can still capture the Compose UI. */
    var skipRenderer = false
    /** Debuggable builds only: store-screenshot hooks (see applyDebugExtras). */
    val debug = DebugHooks()

    class DebugHooks {
        var clean by mutableStateOf(false)
        var show by mutableStateOf<String?>(null)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Always light bar icons: the canvas is black in both system modes.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        sim = SimState(this)
        pro = ProManager(this)
        focus = FocusTimer(this)
        engagement = Engagement(this)
        FocusTimer.ensureChannel(this)
        applyDebugExtras(intent)
        pro.start()
        setContent { BlackHoleTheme { BlackHoleApp(this) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        applyDebugExtras(intent)
    }

    private val debuggable: Boolean
        get() = (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /**
     * Debuggable builds only. `adb shell am start -n <pkg>/com.orchestrsim.blackhole.MainActivity`
     * with: `--ez debug_pro true|false` (force Pro), `--ez debug_no_render true`,
     * `--es debug_scenario M87`, `--es debug_preset ULTRA`, `--ef debug_zoom 30`,
     * `--ez debug_clean true` (hide all UI), `--es debug_show paywall|controls|export|focus|about|welcome|lessons`.
     * Ignored in release builds.
     */
    private fun applyDebugExtras(intent: Intent?) {
        if (!debuggable || intent == null) return
        if (intent.getBooleanExtra("debug_no_render", false)) skipRenderer = true
        if (intent.hasExtra("debug_pro")) pro.setDebugOverride(intent.getBooleanExtra("debug_pro", false))
        intent.getStringExtra("debug_scenario")?.let { n ->
            runCatching { sim.applyScenario(Scenario.valueOf(n), true) }
        }
        intent.getStringExtra("debug_preset")?.let { n -> runCatching { sim.selectPreset(QualityPreset.valueOf(n)) } }
        if (intent.hasExtra("debug_zoom")) { sim.zoom = intent.getFloatExtra("debug_zoom", sim.zoom); sim.pushCamera() }
        if (intent.hasExtra("debug_pitch")) { sim.pitch = intent.getFloatExtra("debug_pitch", sim.pitch); sim.pushCamera() }
        if (intent.hasExtra("debug_clean")) debug.clean = intent.getBooleanExtra("debug_clean", false)
        if (intent.getBooleanExtra("debug_skip_welcome", false)) UiPrefs.markWelcomeSeen(this, onboardPaywall = true)
        debug.show = intent.getStringExtra("debug_show")
        if (intent.getBooleanExtra("debug_export_poster", false)) startPoster()
    }

    override fun onPause() {
        super.onPause()
        NativeBridge.nativeOnPause(true)
        // The live wallpaper follows the look last set in the app.
        if (pro.isPro) runCatching { WallpaperParams.from(sim).save(this) }
    }

    override fun onResume() {
        super.onResume()
        NativeBridge.nativeOnPause(false)
        pro.start()
        focus.tick()
    }

    override fun onDestroy() {
        pro.end()
        super.onDestroy()
    }

    /**
     * A good moment just happened (scenario applied, lesson finished, snapshot
     * or export saved). Shows the one-time paywall or asks for a Play rating,
     * after a short pause so the user first sees the result.
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

    /** Android 8/9 need the legacy storage permission to write to Pictures/Movies. */
    private fun canWriteMedia(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return true
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) return true
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 7)
        return false
    }

    /** Free: copies the current frame of the Vulkan surface into Pictures/BlackHole. */
    fun saveSnapshot() {
        val v = surfaceView ?: return
        if (v.width == 0 || v.height == 0 || !canWriteMedia()) return
        val bmp = Bitmap.createBitmap(v.width, v.height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(v, bmp, { result ->
            if (result != PixelCopy.SUCCESS) {
                Toast.makeText(this, "Couldn't capture the frame.", Toast.LENGTH_SHORT).show()
                return@request
            }
            val ok = MediaSaver.savePng(this, bmp, "BlackHole-${System.currentTimeMillis()}.png")
            Toast.makeText(this, if (ok) "Saved to Pictures/BlackHole" else "Couldn't save the image.", Toast.LENGTH_SHORT).show()
            if (ok) onMoment(Engagement.Moment.SNAPSHOT)
        }, Handler(Looper.getMainLooper()))
    }

    private fun viewSize(): Pair<Int, Int> {
        val v = surfaceView
        return if (v != null && v.width > 0) v.width to v.height
               else resources.displayMetrics.widthPixels to resources.displayMetrics.heightPixels
    }

    fun startPoster() {
        if (!canWriteMedia()) return
        val (w, h) = viewSize()
        lifecycleScope.launch {
            ExportStudio.exportPoster(applicationContext, w, h)
            if (ExportStudio.state is ExportStudio.State.Done) onMoment(Engagement.Moment.SNAPSHOT)
        }
    }

    fun startVideo() {
        if (!canWriteMedia()) return
        val (w, h) = viewSize()
        lifecycleScope.launch {
            ExportStudio.exportOrbitVideo(applicationContext, w, h, sim.diskSpeed)
            if (ExportStudio.state is ExportStudio.State.Done) onMoment(Engagement.Moment.SNAPSHOT)
        }
    }

    /** Pro: hands the current look to the live wallpaper and opens the system preview. */
    fun setLiveWallpaper() {
        runCatching { WallpaperParams.from(sim).save(this) }
        val comp = ComponentName(this, BlackHoleWallpaperService::class.java)
        val tries = listOf(
            Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, comp),
            Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)
        )
        for (i in tries) {
            if (runCatching { startActivity(i) }.isSuccess) return
        }
        Toast.makeText(this, "This device doesn't support live wallpapers.", Toast.LENGTH_LONG).show()
    }

    fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8)
        }
    }
}

/** First-run flags. */
object UiPrefs {
    private fun p(ctx: Context) = ctx.getSharedPreferences("bh.ui", Context.MODE_PRIVATE)
    fun welcomeSeen(ctx: Context) = p(ctx).getBoolean("welcomeSeen", false)
    fun onboardPaywallShown(ctx: Context) = p(ctx).getBoolean("onboardPaywall", false)
    fun markWelcomeSeen(ctx: Context, onboardPaywall: Boolean = false) {
        p(ctx).edit().putBoolean("welcomeSeen", true).apply {
            if (onboardPaywall) putBoolean("onboardPaywall", true)
        }.apply()
    }
    fun markOnboardPaywallShown(ctx: Context) = p(ctx).edit().putBoolean("onboardPaywall", true).apply()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BlackHoleApp(activity: MainActivity) {
    val sim = activity.sim
    val pro = activity.pro
    var showControls by remember { mutableStateOf(false) }
    var showLessons by remember { mutableStateOf(false) }
    var activeLesson by remember { mutableStateOf<Lesson?>(null) }
    var showExport by remember { mutableStateOf(false) }
    var showFocus by remember { mutableStateOf(false) }
    var showAbout by remember { mutableStateOf(false) }
    var showWelcome by remember { mutableStateOf(!UiPrefs.welcomeSeen(activity)) }
    var showMath by remember { mutableStateOf(false) }
    var fps by remember { mutableFloatStateOf(0f) }
    var frameMs by remember { mutableFloatStateOf(0f) }
    var scale by remember { mutableFloatStateOf(1f) }
    val clean = activity.debug.clean || pro.showPaywall

    // Paywall hero: slide the live render up and bring the camera closer so
    // the black hole sits in the clear top of the paywall; restore on close.
    var zoomBeforePaywall by remember { mutableStateOf<Float?>(null) }
    LaunchedEffect(pro.showPaywall) {
        val v = activity.surfaceView
        if (pro.showPaywall) {
            if (zoomBeforePaywall == null) zoomBeforePaywall = sim.zoom
            sim.zoom = minOf(sim.zoom, 44f); sim.pushCamera()
            v?.animate()?.translationY(-(v.height * 0.26f))?.setDuration(450)?.start()
        } else {
            v?.animate()?.translationY(0f)?.setDuration(350)?.start()
            zoomBeforePaywall?.let { sim.zoom = it; sim.pushCamera() }
            zoomBeforePaywall = null
        }
    }

    // Debug screenshot hooks.
    LaunchedEffect(activity.debug.show) {
        when (activity.debug.show) {
            "paywall" -> pro.openPaywall()
            "controls" -> showControls = true
            "export" -> showExport = true
            "focus" -> showFocus = true
            "about" -> showAbout = true
            "welcome" -> showWelcome = true
            "lessons" -> showLessons = true
        }
    }

    // Pro lapsed (refund / expiry): fall back to the best free preset.
    LaunchedEffect(pro.isPro) {
        if (!pro.isPro && sim.preset.isPro) sim.selectPreset(QualityPreset.HIGH)
    }
    LaunchedEffect(pro.justUnlocked) {
        if (pro.justUnlocked) {
            Toast.makeText(activity, "Welcome to BlackHole Pro. Everything is unlocked.", Toast.LENGTH_LONG).show()
            pro.justUnlocked = false
        }
    }

    /** End of onboarding: the one-time, dismissible paywall. */
    fun finishOnboarding() {
        UiPrefs.markWelcomeSeen(activity)
        showWelcome = false
        if (!pro.isPro && !UiPrefs.onboardPaywallShown(activity)) {
            UiPrefs.markOnboardPaywallShown(activity)
            Handler(Looper.getMainLooper()).postDelayed({ if (!pro.isPro) pro.openPaywallAfterOnboarding() }, 700)
        }
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
                fps = out[0]; frameMs = out[1]; scale = out[2]
                delay(250)
            }
        }

        if (!clean) {
            Hud(
                sim, fps, frameMs, scale, showMath, { showMath = !showMath },
                modifier = Modifier.align(Alignment.TopStart).safeDrawingPadding().padding(12.dp)
                    .heightIn(max = 520.dp)
            )

            Row(
                Modifier.align(Alignment.TopEnd).safeDrawingPadding().padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                HomeGlyph(Icons.Outlined.Download, "Save and export") { showExport = true }
                HomeGlyph(Icons.Outlined.Timer, "Focus timer") {
                    if (pro.isPro) showFocus = true else pro.openPaywall("The focus timer")
                }
                HomeGlyph(Icons.Outlined.Tune, "Controls", accent = showControls) { showControls = !showControls }
            }

            // Bottom: lesson card, or Lessons / Pro entry points + credit.
            Column(
                modifier = Modifier.align(Alignment.BottomCenter).safeDrawingPadding()
                    .padding(horizontal = 12.dp).padding(bottom = 10.dp),
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
                        Pill(Icons.Outlined.School, "Lessons", false) { showLessons = true }
                        if (!pro.isPro) {
                            val trial = pro.plans().any { it.trialDays > 0 }
                            Pill(Icons.Outlined.AutoAwesome, if (trial) "Try Pro free" else "Get Pro", true) { pro.openPaywall() }
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Text(
                    "DEVELOPED BY JOHN SEONG AT ORCH AEROSPACE, INC.",
                    color = Color.White.copy(alpha = 0.55f), fontSize = 9.sp,
                    fontWeight = FontWeight.SemiBold, letterSpacing = 2.sp, textAlign = TextAlign.Center, maxLines = 1
                )
            }
        }

        AnimatedVisibility(
            visible = showControls,
            enter = slideInVertically { it },
            exit = slideOutVertically { it },
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            Box(
                Modifier.fillMaxWidth().fillMaxHeight(0.62f)
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .background(Color(0xFA0B0D11))
                    .border(BorderStroke(0.8.dp, Color.White.copy(alpha = 0.12f)), RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .navigationBarsPadding()
            ) {
                ControlPanel(sim, pro, activity.focus,
                    onLessons = { showControls = false; showLessons = true },
                    onExport = { showControls = false; showExport = true },
                    onFocus = { showControls = false; showFocus = true },
                    onWallpaper = { activity.setLiveWallpaper() },
                    onAbout = { showAbout = true },
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

    if (showExport) {
        BhSheet(onDismiss = { if (!ExportStudio.isBusy) { showExport = false; ExportStudio.reset() } }) {
            ExportContent(pro,
                onClose = { showExport = false; ExportStudio.reset() },
                onSaveFrame = { showExport = false; Handler(Looper.getMainLooper()).postDelayed({ activity.saveSnapshot() }, 350) },
                onPoster = { activity.startPoster() },
                onVideo = { activity.startVideo() },
                onWallpaper = { showExport = false; activity.setLiveWallpaper() })
        }
    }
    if (showFocus) {
        BhSheet(onDismiss = { showFocus = false }) {
            FocusContent(activity.focus, onClose = { showFocus = false }, onFirstStart = { activity.ensureNotificationPermission() })
        }
    }
    if (showAbout) {
        BhSheet(onDismiss = { showAbout = false; if (UiPrefs.welcomeSeen(activity)) Unit }) {
            val info = remember { activity.packageManager.getPackageInfo(activity.packageName, 0) }
            @Suppress("DEPRECATION")
            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
            AboutContent(info.versionName ?: "", code, onClose = { showAbout = false })
        }
    }
    if (showWelcome) {
        BhSheet(onDismiss = { finishOnboarding() }) {
            WelcomeContent(
                onLearnMore = { UiPrefs.markWelcomeSeen(activity); showWelcome = false; showAbout = true },
                onStart = { finishOnboarding() })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BhSheet(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = SheetFill,
        contentColor = Color.White,
        scrimColor = Color.Black.copy(alpha = 0.35f)
    ) {
        // The sheet is its own dialog window: keep its navigation bar dark too.
        val view = androidx.compose.ui.platform.LocalView.current
        SideEffect {
            var p: android.view.ViewParent? = view.parent
            while (p != null && p !is androidx.compose.ui.window.DialogWindowProvider) p = p.parent
            (p as? androidx.compose.ui.window.DialogWindowProvider)?.window?.let { w ->
                @Suppress("DEPRECATION")
                w.navigationBarColor = 0xFF07090C.toInt()
                if (Build.VERSION.SDK_INT >= 29) w.isNavigationBarContrastEnforced = false
                androidx.core.view.WindowCompat.getInsetsController(w, w.decorView).isAppearanceLightNavigationBars = false
            }
        }
        content()
    }
}

@Composable
private fun HomeGlyph(icon: ImageVector, label: String, accent: Boolean = false, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(10.dp),
        color = if (accent) Accent.copy(alpha = 0.22f) else Color.Black.copy(alpha = 0.55f),
        border = BorderStroke(0.7.dp, if (accent) Accent.copy(alpha = 0.55f) else Color.White.copy(alpha = 0.10f)),
        modifier = Modifier.size(40.dp)
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
private fun Pill(icon: ImageVector, label: String, accent: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        shape = RoundedCornerShape(10.dp),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
        border = if (accent) null else BorderStroke(0.7.dp, Color.White.copy(alpha = 0.12f)),
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
