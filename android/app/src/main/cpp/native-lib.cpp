// JNI surface lifecycle + render thread. The Renderer owns Vulkan and is
// created/destroyed on a dedicated thread tied to the Android Surface.
#include "renderer.h"

#include <jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>

#define LOG_TAG "BlackHoleVk"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

namespace {
std::mutex          g_mutex;
Renderer*           g_renderer = nullptr;
std::thread         g_thread;
std::atomic<bool>   g_running{false};
std::atomic<bool>   g_paused{false};
ANativeWindow*      g_window = nullptr;
std::atomic<float>  g_frameCap{0.0f};   // 0 = display rate (FIFO)

// Work that must run on the render thread (exports). The caller blocks until
// the job ran, or until the render thread exits (job reports failure).
struct Job {
    std::function<bool(Renderer*)> fn;
    bool done = false;
    bool ok = false;
};
std::mutex                         g_jobMutex;
std::condition_variable            g_jobCv;
std::deque<std::shared_ptr<Job>>   g_jobs;

void drainJobs(Renderer* r) {
    for (;;) {
        std::shared_ptr<Job> j;
        {
            std::lock_guard<std::mutex> lk(g_jobMutex);
            if (g_jobs.empty()) return;
            j = g_jobs.front();
            g_jobs.pop_front();
        }
        bool ok = r ? j->fn(r) : false;
        {
            std::lock_guard<std::mutex> lk(g_jobMutex);
            j->ok = ok;
            j->done = true;
        }
        g_jobCv.notify_all();
    }
}

bool runOnRenderThread(std::function<bool(Renderer*)> fn) {
    if (!g_running.load()) return false;
    auto j = std::make_shared<Job>();
    j->fn = std::move(fn);
    std::unique_lock<std::mutex> lk(g_jobMutex);
    g_jobs.push_back(j);
    while (!j->done) {
        g_jobCv.wait_for(lk, std::chrono::milliseconds(100));
        if (!j->done && !g_running.load()) {
            // Render thread is gone; drop the job if it never started.
            for (auto it = g_jobs.begin(); it != g_jobs.end(); ++it) {
                if (*it == j) { g_jobs.erase(it); return false; }
            }
        }
    }
    return j->ok;
}

double monoNow() {
    return std::chrono::duration<double>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

void renderLoop(ANativeWindow* window) {
    auto* r = new Renderer();
    if (!r->init(window)) {
        LOGI("Renderer init failed");
        delete r;
        ANativeWindow_release(window);
        return;
    }
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        g_renderer = r;
        float cap = g_frameCap.load();
        if (cap > 0.0f) r->setTargetFps(cap);
    }
    while (g_running.load()) {
        drainJobs(r);
        if (g_paused.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(16));
            continue;
        }
        double start = monoNow();
        r->drawFrame();   // FIFO present paces this to the display refresh
        float cap = g_frameCap.load();
        if (cap > 0.0f) {
            double wait = 1.0 / cap - (monoNow() - start);
            if (wait > 0.0) std::this_thread::sleep_for(std::chrono::duration<double>(wait));
        }
    }
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        g_renderer = nullptr;
    }
    drainJobs(nullptr);   // fail anything still queued
    r->shutdown();
    delete r;
    ANativeWindow_release(window);
}
}  // namespace

extern "C" {

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeOnSurfaceCreated(
        JNIEnv* env, jobject, jobject surface) {
    if (g_running.load()) return;
    g_window = ANativeWindow_fromSurface(env, surface);
    if (!g_window) return;
    g_running.store(true);
    g_paused.store(false);
    g_thread = std::thread(renderLoop, g_window);
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeOnSurfaceChanged(
        JNIEnv*, jobject, jint width, jint height) {
    std::lock_guard<std::mutex> lk(g_mutex);
    if (g_renderer) g_renderer->resize(width, height);
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeOnSurfaceDestroyed(
        JNIEnv*, jobject) {
    g_running.store(false);
    if (g_thread.joinable()) g_thread.join();
    g_window = nullptr;
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeOnPause(
        JNIEnv*, jobject, jboolean paused) {
    g_paused.store(paused == JNI_TRUE);
    std::lock_guard<std::mutex> lk(g_mutex);
    if (g_renderer) g_renderer->setPaused(paused == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeSetParams(
        JNIEnv* env, jobject, jfloatArray jf, jintArray ji) {
    jfloat f[16] = {0};
    jint   i[4] = {0};
    jsize  nf = env->GetArrayLength(jf);
    jsize  ni = env->GetArrayLength(ji);
    env->GetFloatArrayRegion(jf, 0, nf < 16 ? nf : 16, f);
    env->GetIntArrayRegion(ji, 0, ni < 4 ? ni : 4, i);

    InputState s;
    s.mass = f[0]; s.spin = f[1]; s.lensingStrength = f[2]; s.frameDragStrength = f[3];
    s.diskDensity = f[4]; s.diskTemp = f[5]; s.diskSize = f[6]; s.diskScaleHeight = f[7];
    s.bloomThreshold = f[8]; s.bloomIntensity = f[9]; s.autoSpin = f[10];
    s.renderScale = f[14];
    s.diskSpeed = f[15];
    s.maxRaySteps = i[0];
    s.flagsMask = (uint8_t)i[1];
    s.taaEnabled = i[2] != 0;
    s.bloomEnabled = i[3] != 0;

    std::lock_guard<std::mutex> lk(g_mutex);
    if (g_renderer) g_renderer->setParams(s);
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeSetCamera(
        JNIEnv*, jobject, jfloat yaw, jfloat pitch, jfloat zoom) {
    std::lock_guard<std::mutex> lk(g_mutex);
    if (g_renderer) g_renderer->setCamera(yaw, pitch, zoom);
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeGetTelemetry(
        JNIEnv* env, jobject, jfloatArray out) {
    Telemetry t;
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        if (g_renderer) t = g_renderer->telemetry();
    }
    jfloat vals[3] = {t.fps, t.frameTimeMs, t.effectiveScale};
    env->SetFloatArrayRegion(out, 0, 3, vals);
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeSetFrameCap(
        JNIEnv*, jobject, jfloat fps) {
    g_frameCap.store(fps > 0.0f ? fps : 0.0f);
    std::lock_guard<std::mutex> lk(g_mutex);
    if (g_renderer) g_renderer->setTargetFps(fps > 0.0f ? fps : 60.0);
}

// out: [yaw, pitch, zoom, time, diskTime]
JNIEXPORT jboolean JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeExportCamera(
        JNIEnv* env, jobject, jfloatArray out) {
    ExportCamera c;
    bool ok = runOnRenderThread([&](Renderer* r) { c = r->currentCamera(); return true; });
    if (!ok) return JNI_FALSE;
    jfloat v[5] = {c.yaw, c.pitch, c.zoom, c.time, c.diskTime};
    env->SetFloatArrayRegion(out, 0, 5, v);
    return JNI_TRUE;
}

// cam: [yaw, pitch, zoom, time, diskTime]. `out` is a direct ByteBuffer of
// w*h*4 bytes, written on the last pass only (may be null otherwise).
JNIEXPORT jboolean JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeExportPass(
        JNIEnv* env, jobject, jint w, jint h, jfloatArray jcam, jint raySteps,
        jint passIndex, jint passCount, jobject out) {
    jfloat v[5] = {0};
    env->GetFloatArrayRegion(jcam, 0, 5, v);
    ExportCamera c{v[0], v[1], v[2], v[3], v[4]};
    uint8_t* dst = nullptr;
    if (out) {
        dst = (uint8_t*)env->GetDirectBufferAddress(out);
        jlong cap = env->GetDirectBufferCapacity(out);
        if (!dst || cap < (jlong)w * h * 4) return JNI_FALSE;
    }
    bool ok = runOnRenderThread([&](Renderer* r) {
        return r->exportPass((uint32_t)w, (uint32_t)h, c, raySteps, passIndex, passCount, dst);
    });
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeExportEnd(JNIEnv*, jobject) {
    runOnRenderThread([](Renderer* r) { r->releaseExport(); return true; });
}

}  // extern "C"
