import SwiftUI

/// Guided physics lessons. Each one sets the simulator to a configuration
/// that shows one effect clearly, explains it in plain language, and ends
/// with a "try this" prompt so the user changes something and sees the
/// physics respond. The first two are free; the rest ship with Pro.
enum Lesson: Int, CaseIterable, Identifiable {
    case shadow, lensing, doppler, redshift, spin, isco, temperature, jets

    var id: Int { rawValue }
    var number: Int { rawValue + 1 }
    static let freeCount = 2
    var isPro: Bool { rawValue >= Self.freeCount }

    var title: String {
        switch self {
        case .shadow:      return "The shadow"
        case .lensing:     return "Gravitational lensing"
        case .doppler:     return "Doppler beaming"
        case .redshift:    return "Gravitational redshift"
        case .spin:        return "Spin and frame dragging"
        case .isco:        return "The innermost stable orbit"
        case .temperature: return "Disk temperature and colour"
        case .jets:        return "Relativistic jets"
        }
    }

    var symbol: String {
        switch self {
        case .shadow:      return "eye"
        case .lensing:     return "camera.filters"
        case .doppler:     return "arrow.left.and.right"
        case .redshift:    return "thermometer.low"
        case .spin:        return "arrow.clockwise"
        case .isco:        return "scope"
        case .temperature: return "flame"
        case .jets:        return "arrow.up.and.down"
        }
    }

    var summary: String {
        switch self {
        case .shadow:      return "Why the dark disc is bigger than the hole."
        case .lensing:     return "How the disk wraps over the top."
        case .doppler:     return "Why one side is brighter."
        case .redshift:    return "Light losing energy as it climbs out."
        case .spin:        return "Kerr holes drag spacetime around."
        case .isco:        return "Where the disk has to end."
        case .temperature: return "Blackbody light from the disk."
        case .jets:        return "Beams along the spin axis."
        }
    }

    var body: String {
        switch self {
        case .shadow:
            return "This is a non-rotating (Schwarzschild) black hole. Its event horizon sits at r = 2M. At r = 3M is the photon sphere, where light can circle the hole. Rays that pass inside it spiral in, so the dark shadow you see has an apparent radius of √27 M, about 5.2M: roughly 2.6 times the horizon. Gravity magnifies the hole's own silhouette."
        case .lensing:
            return "The disk is flat, but you see it arch over the top and under the bottom of the shadow. That is light from the far side of the disk, bent around the hole on its way to the camera. Thin rings closer to the shadow are higher-order images: light that went half or fully around the hole before escaping."
        case .doppler:
            return "Near the inner edge the gas orbits at a large fraction of the speed of light. The side moving toward you is blue-shifted and beamed, the receding side is dimmed. The renderer scales observed intensity as δ^3.5, where δ is the relativistic Doppler factor, which is why the disk looks lopsided."
        case .redshift:
            return "Light that climbs out of a deep gravity well arrives with less energy. This view colours each ray by the gravitational redshift factor √(1 − 2M/r) at its closest approach to the hole, a Schwarzschild approximation. Blue rays stayed far out, yellow and red ones dipped deep into the well, and black ones were captured. At the horizon the factor reaches zero: light from there is redshifted out of sight."
        case .spin:
            return "A spinning (Kerr) hole drags spacetime with it. The horizon shrinks from 2M toward M as spin a* approaches 1, and outside it the ergosphere appears, a region where nothing can stay still relative to distant stars. The shadow flattens on the side rotating toward you."
        case .isco:
            return "Gas can only orbit stably down to the innermost stable circular orbit (ISCO). For a non-rotating hole it is at 6M. A disk orbiting with the spin can reach closer (about 1.5M at a* = 0.99); one orbiting against it is pushed out toward 9M. Watch the inner edge of the disk move."
        case .temperature:
            return "Each ring of the disk glows like a blackbody. In the Novikov–Thorne model temperature rises inward roughly as r^(-3/4) before falling off at the ISCO. Hotter disks look blue-white, cooler ones orange. Smaller holes have hotter disks: T scales roughly as M^(-1/4)."
        case .jets:
            return "Many black holes launch narrow jets along their spin axis. In the Blandford–Znajek picture, magnetic fields threading the horizon tap the hole's rotational energy, and jet power rises steeply with spin. The jets drawn here are a visual model aligned with the spin axis, not a magnetohydrodynamic simulation."
        }
    }

    var tryThis: String {
        switch self {
        case .shadow:      return "Pinch to zoom in. Compare the shadow's edge with the horizon and photon-sphere radii in the HUD."
        case .lensing:     return "Open Controls and turn Lensing off under Effects. The disk collapses back into a flat ring."
        case .doppler:     return "Toggle Doppler under Effects, then drag around the hole and watch the bright side follow the orbit."
        case .redshift:    return "Zoom in and out, then turn Redshift off under Effects to compare with the normal image."
        case .spin:        return "Drag Spin from 0 to 0.99 and watch the horizon and photon-sphere readouts shrink."
        case .isco:        return "Drag Spin from -0.9 to +0.9 and watch the ISCO value in the HUD and the disk's inner edge."
        case .temperature: return "Sweep Temperature from 1,000 K to 50,000 K."
        case .jets:        return "Orbit the camera to look down the jet, then turn Jets off under Effects to compare."
        }
    }

    @MainActor
    func apply(to p: BlackHoleParameters) {
        // Baseline: a clean, mid-quality view every lesson builds on.
        p.enableLensing = true
        p.enableDisk = true
        p.enableDoppler = true
        p.enablePhotonGlow = true
        p.enableStars = true
        p.enableJets = false
        p.showRedshift = false
        p.lensingStrength = 1.0
        p.frameDragStrength = 2.0
        p.diskDensity = 4.0
        p.diskScaleHeight = 0.15
        p.pitch = 0.539
        p.mass = 1.0

        switch self {
        case .shadow:
            p.spin = 0.0; p.diskSize = 40; p.diskTemp = 9000; p.zoom = 22
        case .lensing:
            p.spin = 0.5; p.diskSize = 50; p.diskTemp = 10000; p.zoom = 30; p.pitch = 0.52
        case .doppler:
            p.spin = 0.9; p.diskSize = 40; p.diskTemp = 12000; p.zoom = 28; p.pitch = 0.51
        case .redshift:
            p.spin = 0.6; p.diskSize = 40; p.diskTemp = 10000; p.zoom = 26; p.showRedshift = true
        case .spin:
            p.spin = 0.99; p.diskSize = 35; p.diskTemp = 14000; p.zoom = 22
        case .isco:
            p.spin = -0.9; p.diskSize = 45; p.diskTemp = 12000; p.zoom = 30; p.pitch = 0.30
        case .temperature:
            p.spin = 0.7; p.diskSize = 60; p.diskTemp = 4000; p.zoom = 45; p.pitch = 0.40
        case .jets:
            p.spin = 0.95; p.diskSize = 50; p.diskTemp = 15000; p.zoom = 70; p.pitch = 0.45; p.enableJets = true
        }
        if p.preset == .low { p.preset = .medium }
    }
}

/// Lesson index. Free lessons open directly; locked ones open the paywall.
struct LessonsSheet: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var ui: UIState
    @Environment(\.dismiss) private var dismiss

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lessons")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Eight short guided tours of the physics on screen. Each sets up the simulator, explains what you are seeing, and gives you something to try.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Lesson.allCases) { lesson in
                        row(lesson)
                    }
                }
            }
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
        .background(Color.black.opacity(0.92))
        .colorScheme(.dark)
    }

    private func row(_ lesson: Lesson) -> some View {
        let locked = lesson.isPro && !subscription.isProUnlocked
        return Button {
            if locked {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    subscription.requestPaywall = true
                }
            } else {
                lesson.apply(to: params)
                ui.activeLesson = lesson
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: lesson.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(cyan)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(lesson.number). \(lesson.title)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        if locked { ProBadge() }
                    }
                    Text(lesson.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.58))
                }
                Spacer()
                Image(systemName: locked ? "lock" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bottom card shown over the live simulation while a lesson is active.
struct LessonCard: View {
    let lesson: Lesson
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var ui: UIState
    @State private var expanded = true

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: lesson.symbol)
                    .font(.system(size: 13))
                    .foregroundColor(cyan)
                Text("LESSON \(lesson.number) OF \(Lesson.allCases.count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(cyan.opacity(0.85))
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse" : "Expand")
                Button { ui.activeLesson = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End lesson")
            }
            Text(lesson.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.body)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "hand.point.up.left")
                                .font(.system(size: 11))
                                .foregroundColor(cyan)
                            Text(lesson.tryThis)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(cyan.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
            HStack {
                if let prev = Lesson(rawValue: lesson.rawValue - 1) {
                    navButton("Previous", symbol: "chevron.left", locked: false) { go(prev) }
                }
                Spacer()
                if let next = Lesson(rawValue: lesson.rawValue + 1) {
                    let locked = next.isPro && !subscription.isProUnlocked
                    navButton(locked ? "Next lesson with Pro" : "Next: \(next.title)",
                              symbol: locked ? "lock" : "chevron.right",
                              locked: locked) { go(next) }
                } else {
                    navButton("Finish", symbol: "checkmark", locked: false) { ui.activeLesson = nil }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.40))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
        .colorScheme(.dark)
    }

    private func go(_ l: Lesson) {
        if l.isPro && !subscription.isProUnlocked {
            subscription.requestPaywall = true
            return
        }
        l.apply(to: params)
        withAnimation(.easeInOut(duration: 0.2)) { ui.activeLesson = l }
    }

    private func navButton(_ title: String, symbol: String, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if symbol == "chevron.left" {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if symbol != "chevron.left" {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundColor(locked ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(locked ? cyan : Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Small "PRO" tag used next to locked items.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundColor(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.55, green: 0.95, blue: 1.0)))
    }
}
