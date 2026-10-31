// JNI surface lifecycle + render thread. The Renderer owns Vulkan and is
// created/destroyed on a dedicated thread tied to the Android Surface.
#include "renderer.h"

#include <jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>

#include <atomic>
#include <chrono>
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
    }
    while (g_running.load()) {
        if (g_paused.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(32));
            continue;
        }
        r->drawFrame();   // FIFO present paces this to the display refresh
    }
    {
        std::lock_guard<std::mutex> lk(g_mutex);
        g_renderer = nullptr;
    }
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

}  // extern "C"
