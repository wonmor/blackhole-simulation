package com.orchestrsim.blackhole.model

/**
 * Curated educational presets, mirroring the iOS `Scenario` enum. The first
 * four are free; the rest ship with BlackHole Pro. Every scenario sets the
 * effect toggles too, so switching never leaves a stray effect behind.
 */
enum class Scenario(val displayName: String, val subtitle: String, val isPro: Boolean) {
    // Glyphs for the scenario cards live in ui/ControlPanel.kt (scenarioGlyph).
    STELLAR("Stellar", "10 M☉ | a=0.5 | hot disk", false),
    SGR_A("Sgr A* proxy", "Supermassive proxy | a=0.94", false),
    MAXIMAL_SPIN("Maximal Spin", "Near-Kerr extremal | a=0.99", false),
    SCHWARZSCHILD("Schwarzschild", "Non-rotating | classic ring", false),
    M87("M87* (EHT view)", "Near face-on | a=0.9 | jets", true),
    GARGANTUA("Film look", "Thin cool disk | no Doppler", true),
    RETROGRADE("Retrograde disk", "a=-0.9 | ISCO pushed out", true),
    CYGNUS_X1("Cygnus X-1", "X-ray binary | a=0.95", true),
    QUASAR("Quasar", "40,000 K disk | jets", true),
    BARE_SHADOW("Bare shadow", "No disk | lensed stars only", true);

    fun apply(p: SimState) {
        p.enableLensing = true; p.enableDisk = true; p.enableDoppler = true
        p.enablePhotonGlow = true; p.enableStars = true; p.enableJets = true
        p.showRedshift = false; p.frameDragStrength = 2.0f
        p.bloomThreshold = 1.0f; p.bloomIntensity = 0.45f; p.pitch = 0.539f
        val keepCine = p.preset == QualityPreset.CINEMATIC
        when (this) {
            STELLAR -> {
                p.mass = 10.0f; p.spin = 0.50f; p.lensingStrength = 0.7f
                p.diskSize = 80.0f; p.diskTemp = 15000.0f; p.diskDensity = 4.0f
                p.diskScaleHeight = 0.18f; p.zoom = 80.0f
                p.preset = QualityPreset.HIGH
            }
            SGR_A -> {
                p.mass = 4.0f; p.spin = 0.94f; p.lensingStrength = 0.9f
                p.diskSize = 60.0f; p.diskTemp = 8000.0f; p.diskDensity = 3.5f
                p.diskScaleHeight = 0.20f; p.zoom = 60.0f
                p.preset = QualityPreset.HIGH
            }
            MAXIMAL_SPIN -> {
                p.mass = 2.0f; p.spin = 0.99f; p.lensingStrength = 1.2f
                p.diskSize = 40.0f; p.diskTemp = 20000.0f; p.diskDensity = 4.5f
                p.diskScaleHeight = 0.15f; p.zoom = 30.0f
                p.preset = QualityPreset.ULTRA
            }
            SCHWARZSCHILD -> {
                p.mass = 1.0f; p.spin = 0.0f; p.lensingStrength = 0.7f
                p.diskSize = 50.0f; p.diskTemp = 9500.0f; p.diskDensity = 4.0f
                p.diskScaleHeight = 0.20f; p.zoom = 30.0f; p.enableJets = false
                p.preset = QualityPreset.HIGH
            }
            M87 -> {
                p.mass = 6.5f; p.spin = 0.90f; p.lensingStrength = 1.0f
                p.diskSize = 45.0f; p.diskTemp = 6000.0f; p.diskDensity = 3.0f
                p.diskScaleHeight = 0.22f; p.zoom = 55.0f; p.pitch = 0.12f
                p.bloomIntensity = 0.7f; p.preset = QualityPreset.ULTRA
            }
            GARGANTUA -> {
                p.mass = 3.0f; p.spin = 0.99f; p.lensingStrength = 1.0f
                p.diskSize = 30.0f; p.diskTemp = 4500.0f; p.diskDensity = 5.0f
                p.diskScaleHeight = 0.05f; p.zoom = 25.0f; p.pitch = 0.51f
                p.enableDoppler = false; p.enableJets = false
                p.preset = QualityPreset.ULTRA
            }
            RETROGRADE -> {
                p.mass = 2.0f; p.spin = -0.90f; p.lensingStrength = 1.0f
                p.diskSize = 50.0f; p.diskTemp = 12000.0f; p.diskDensity = 4.0f
                p.diskScaleHeight = 0.15f; p.zoom = 35.0f; p.enableJets = false
                p.preset = QualityPreset.ULTRA
            }
            CYGNUS_X1 -> {
                p.mass = 10.0f; p.spin = 0.95f; p.lensingStrength = 0.9f
                p.diskSize = 35.0f; p.diskTemp = 32000.0f; p.diskDensity = 4.5f
                p.diskScaleHeight = 0.12f; p.zoom = 40.0f
                p.preset = QualityPreset.ULTRA
            }
            QUASAR -> {
                p.mass = 8.0f; p.spin = 0.98f; p.lensingStrength = 1.0f
                p.diskSize = 100.0f; p.diskTemp = 40000.0f; p.diskDensity = 5.0f
                p.diskScaleHeight = 0.25f; p.zoom = 90.0f; p.pitch = 0.40f
                p.bloomIntensity = 1.0f; p.preset = QualityPreset.ULTRA
            }
            BARE_SHADOW -> {
                p.mass = 1.0f; p.spin = 0.70f; p.lensingStrength = 1.4f
                p.diskSize = 50.0f; p.diskTemp = 9500.0f; p.diskDensity = 4.0f
                p.diskScaleHeight = 0.20f; p.zoom = 18.0f
                p.enableDisk = false; p.enableJets = false
                p.preset = QualityPreset.ULTRA
            }
        }
        if (keepCine) p.preset = QualityPreset.CINEMATIC
    }
}
