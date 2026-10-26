package com.orchestrsim.blackhole.model

/**
 * Guided physics lessons (text shared with the iOS `Lesson` enum). Each sets
 * the simulator up to show one effect, explains it, and ends with something
 * to try. The first two are free; the rest ship with BlackHole Pro.
 */
enum class Lesson(val title: String, val summary: String, val body: String, val tryThis: String) {
    SHADOW(
        "The shadow",
        "Why the dark disc is bigger than the hole.",
        "This is a non-rotating (Schwarzschild) black hole. Its event horizon sits at r = 2M. At r = 3M is the photon sphere, where light can circle the hole. Rays that pass inside it spiral in, so the dark shadow you see has an apparent radius of √27 M, about 5.2M: roughly 2.6 times the horizon. Gravity magnifies the hole's own silhouette.",
        "Pinch to zoom in. Compare the shadow's edge with the horizon and photon-sphere radii in the HUD."
    ),
    LENSING(
        "Gravitational lensing",
        "How the disk wraps over the top.",
        "The disk is flat, but you see it arch over the top and under the bottom of the shadow. That is light from the far side of the disk, bent around the hole on its way to the camera. Thin rings closer to the shadow are higher-order images: light that went half or fully around the hole before escaping.",
        "Open Controls and turn Lensing off under Effects. The disk collapses back into a flat ring."
    ),
    DOPPLER(
        "Doppler beaming",
        "Why one side is brighter.",
        "Near the inner edge the gas orbits at a large fraction of the speed of light. The side moving toward you is blue-shifted and beamed, the receding side is dimmed. The renderer scales observed intensity as δ^3.5, where δ is the relativistic Doppler factor, which is why the disk looks lopsided.",
        "Toggle Doppler under Effects, then drag around the hole and watch the bright side follow the orbit."
    ),
    REDSHIFT(
        "Gravitational redshift",
        "Light losing energy as it climbs out.",
        "Light that climbs out of a deep gravity well arrives with less energy. This view colours each ray by the gravitational redshift factor √(1 − 2M/r) at its closest approach to the hole, a Schwarzschild approximation. Blue rays stayed far out, yellow and red ones dipped deep into the well, and black ones were captured. At the horizon the factor reaches zero: light from there is redshifted out of sight.",
        "Zoom in and out, then turn Redshift off under Effects to compare with the normal image."
    ),
    SPIN(
        "Spin and frame dragging",
        "Kerr holes drag spacetime around.",
        "A spinning (Kerr) hole drags spacetime with it. The horizon shrinks from 2M toward M as spin a* approaches 1, and outside it the ergosphere appears, a region where nothing can stay still relative to distant stars. The shadow flattens on the side rotating toward you.",
        "Drag Spin from 0 to 0.99 and watch the horizon and photon-sphere readouts shrink."
    ),
    ISCO(
        "The innermost stable orbit",
        "Where the disk has to end.",
        "Gas can only orbit stably down to the innermost stable circular orbit (ISCO). For a non-rotating hole it is at 6M. A disk orbiting with the spin can reach closer (about 1.5M at a* = 0.99); one orbiting against it is pushed out toward 9M. Watch the inner edge of the disk move.",
        "Drag Spin from -0.9 to +0.9 and watch the ISCO value in the HUD and the disk's inner edge."
    ),
    TEMPERATURE(
        "Disk temperature and colour",
        "Blackbody light from the disk.",
        "Each ring of the disk glows like a blackbody. In the Novikov–Thorne model temperature rises inward roughly as r^(-3/4) before falling off at the ISCO. Hotter disks look blue-white, cooler ones orange. Smaller holes have hotter disks: T scales roughly as M^(-1/4).",
        "Sweep Temperature from 1,000 K to 50,000 K."
    ),
    JETS(
        "Relativistic jets",
        "Beams along the spin axis.",
        "Many black holes launch narrow jets along their spin axis. In the Blandford–Znajek picture, magnetic fields threading the horizon tap the hole's rotational energy, and jet power rises steeply with spin. The jets drawn here are a visual model aligned with the spin axis, not a magnetohydrodynamic simulation.",
        "Orbit the camera to look down the jet, then turn Jets off under Effects to compare."
    );

    val number: Int get() = ordinal + 1
    val isPro: Boolean get() = ordinal >= FREE_COUNT

    fun apply(p: SimState) {
        p.enableLensing = true; p.enableDisk = true; p.enableDoppler = true
        p.enablePhotonGlow = true; p.enableStars = true; p.enableJets = false
        p.showRedshift = false; p.lensingStrength = 1.0f; p.frameDragStrength = 2.0f
        p.diskDensity = 4.0f; p.diskScaleHeight = 0.15f; p.pitch = 0.539f; p.mass = 1.0f
        when (this) {
            SHADOW -> { p.spin = 0.0f; p.diskSize = 40f; p.diskTemp = 9000f; p.zoom = 22f }
            LENSING -> { p.spin = 0.5f; p.diskSize = 50f; p.diskTemp = 10000f; p.zoom = 30f; p.pitch = 0.52f }
            DOPPLER -> { p.spin = 0.9f; p.diskSize = 40f; p.diskTemp = 12000f; p.zoom = 28f; p.pitch = 0.51f }
            REDSHIFT -> { p.spin = 0.6f; p.diskSize = 40f; p.diskTemp = 10000f; p.zoom = 26f; p.showRedshift = true }
            SPIN -> { p.spin = 0.99f; p.diskSize = 35f; p.diskTemp = 14000f; p.zoom = 22f }
            ISCO -> { p.spin = -0.9f; p.diskSize = 45f; p.diskTemp = 12000f; p.zoom = 30f; p.pitch = 0.30f }
            TEMPERATURE -> { p.spin = 0.7f; p.diskSize = 60f; p.diskTemp = 4000f; p.zoom = 45f; p.pitch = 0.40f }
            JETS -> { p.spin = 0.95f; p.diskSize = 50f; p.diskTemp = 15000f; p.zoom = 70f; p.pitch = 0.45f; p.enableJets = true }
        }
        if (p.preset == QualityPreset.LOW) p.preset = QualityPreset.MEDIUM
    }

    companion object { const val FREE_COUNT = 2 }
}
