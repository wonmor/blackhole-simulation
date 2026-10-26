// JNI bridge to the Rust gravitas-ffi static library (Kerr observables).
// The archive is cross-compiled per ABI by the cargo Gradle task and linked by
// CMake. These mirror the Swift `Gravitas` enum used by the Apple app.
#include <jni.h>

extern "C" {
// Declared in physics-engine/gravitas-ffi/include/gravitas.h
double  gravitas_kerr_horizon(double mass, double spin);
double  gravitas_kerr_photon_sphere(double mass, double spin);
double  gravitas_kerr_isco(double mass, double spin, int prograde);
double  gravitas_kerr_ergosphere(double mass, double spin, double cos_theta);
const char* gravitas_version(void);
}

extern "C" {

JNIEXPORT jdouble JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeKerrHorizon(
        JNIEnv*, jobject, jdouble mass, jdouble spin) {
    return gravitas_kerr_horizon(mass, spin);
}

JNIEXPORT jdouble JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeKerrPhotonSphere(
        JNIEnv*, jobject, jdouble mass, jdouble spin) {
    return gravitas_kerr_photon_sphere(mass, spin);
}

JNIEXPORT jdouble JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeKerrIsco(
        JNIEnv*, jobject, jdouble mass, jdouble spin, jboolean prograde) {
    return gravitas_kerr_isco(mass, spin, prograde == JNI_TRUE ? 1 : 0);
}

JNIEXPORT jdouble JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeKerrErgosphere(
        JNIEnv*, jobject, jdouble mass, jdouble spin, jdouble cosTheta) {
    return gravitas_kerr_ergosphere(mass, spin, cosTheta);
}

JNIEXPORT jstring JNICALL
Java_com_orchestrsim_blackhole_NativeBridge_nativeGravitasVersion(
        JNIEnv* env, jobject) {
    return env->NewStringUTF(gravitas_version());
}

}  // extern "C"
