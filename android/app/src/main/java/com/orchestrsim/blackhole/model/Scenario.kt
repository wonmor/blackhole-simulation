package com.orchestrsim.blackhole.model

/** Curated educational presets, mirroring the iOS `Scenario` enum. */
enum class Scenario(val displayName: String, val subtitle: String) {
    STELLAR("Stellar", "10 M☉ · a=0.5 · hot disk"),
    SGR_A("Sgr A* proxy", "Supermassive proxy · a=0.94"),
    MAXIMAL_SPIN("Maximal Spin", "Near-Kerr extremal · a=0.99"),
    SCHWARZSCHILD("Schwarzschild", "Non-rotating · classic ring");

    fun apply(p: SimState) {
        when (this) {
            STELLAR -> {
                p.mass = 10.0f; p.spin = 0.50f; p.lensingStrength = 0.7f
                p.diskSize = 80.0f; p.diskTemp = 15000.0f; p.diskDensity = 4.0f
                p.diskScaleHeight = 0.18f; p.zoom = 80.0f; p.pitch = 0.539f
                p.preset = QualityPreset.HIGH
            }
            SGR_A -> {
                p.mass = 4.0f; p.spin = 0.94f; p.lensingStrength = 0.9f
                p.diskSize = 60.0f; p.diskTemp = 8000.0f; p.diskDensity = 3.5f
                p.diskScaleHeight = 0.20f; p.zoom = 60.0f; p.pitch = 0.539f
                p.preset = QualityPreset.HIGH
            }
            MAXIMAL_SPIN -> {
                p.mass = 2.0f; p.spin = 0.99f; p.lensingStrength = 1.2f
                p.diskSize = 40.0f; p.diskTemp = 20000.0f; p.diskDensity = 4.5f
                p.diskScaleHeight = 0.15f; p.zoom = 30.0f; p.pitch = 0.539f
                p.preset = QualityPreset.ULTRA
            }
            SCHWARZSCHILD -> {
                p.mass = 1.0f; p.spin = 0.0f; p.lensingStrength = 0.7f
                p.diskSize = 50.0f; p.diskTemp = 9500.0f; p.diskDensity = 4.0f
                p.diskScaleHeight = 0.20f; p.zoom = 30.0f; p.pitch = 0.539f
                p.preset = QualityPreset.HIGH
            }
        }
    }
}
