// RGBA8 -> YUV 4:2:0 for the MediaCodec orbit-video encoder. Writes into the
// planes of an android.media.Image (any row/pixel stride, so it handles both
// I420 and NV12/NV21 layouts behind COLOR_FormatYUV420Flexible). BT.601
// limited range, which is what H.264 decoders assume by default.
#include <jni.h>
#include <cstdint>

static inline uint8_t clamp8(int v) { return (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v)); }

extern "C" JNIEXPORT jboolean JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeRgbaToYuv(
        JNIEnv* env, jobject, jobject rgba, jint w, jint h,
        jobject yBuf, jint yRow, jint yPix,
        jobject uBuf, jint uRow, jint uPix,
        jobject vBuf, jint vRow, jint vPix) {
    auto* src = (const uint8_t*)env->GetDirectBufferAddress(rgba);
    auto* yp = (uint8_t*)env->GetDirectBufferAddress(yBuf);
    auto* up = (uint8_t*)env->GetDirectBufferAddress(uBuf);
    auto* vp = (uint8_t*)env->GetDirectBufferAddress(vBuf);
    if (!src || !yp || !up || !vp) return JNI_FALSE;
    for (int y = 0; y < h; ++y) {
        const uint8_t* row = src + (size_t)y * w * 4;
        uint8_t* yr = yp + (size_t)y * yRow;
        for (int x = 0; x < w; ++x) {
            int r = row[x * 4], g = row[x * 4 + 1], b = row[x * 4 + 2];
            yr[(size_t)x * yPix] = clamp8(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
        }
    }
    for (int y = 0; y < h / 2; ++y) {
        const uint8_t* r0 = src + (size_t)(2 * y) * w * 4;
        const uint8_t* r1 = r0 + (size_t)w * 4;
        uint8_t* ur = up + (size_t)y * uRow;
        uint8_t* vr = vp + (size_t)y * vRow;
        for (int x = 0; x < w / 2; ++x) {
            int i = x * 8;
            int r = (r0[i] + r0[i + 4] + r1[i] + r1[i + 4]) >> 2;
            int g = (r0[i + 1] + r0[i + 5] + r1[i + 1] + r1[i + 5]) >> 2;
            int b = (r0[i + 2] + r0[i + 6] + r1[i + 2] + r1[i + 6]) >> 2;
            ur[(size_t)x * uPix] = clamp8(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
            vr[(size_t)x * vPix] = clamp8(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
        }
    }
    return JNI_TRUE;
}
