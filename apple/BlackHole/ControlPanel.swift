import SwiftUI

/// User-facing parameter editor.
/// Visual language matches `HUDView`: ultraThinMaterial over a dark scrim, a
/// subtle white-gradient border, soft shadow, cyan accent for section headers
/// and active states, tabular-monospace numerics.
struct ControlPanel: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var pomodoro: PomodoroTimer

    /// Fired when user taps the Pomodoro button AND has Pro. Container
    /// presents `PomodoroView` (sheet on iOS, window on macOS).
    var onPomodoroTap: () -> Void = {}
    /// iOS-only "Save as Wallpaper" handler. nil → button hidden.
    var onWallpaperSaveTap: (() -> Void)? = nil
    /// macOS-only "Set/Stop Live Wallpaper" handler. nil → button hidden.
    var onLiveWallpaperToggle: (() -> Void)? = nil
    /// macOS-only state — true if wallpaper mode is currently active.
    /// Drives the button label / icon.
    var liveWallpaperActive: Bool = false
    /// Tapped on the header info button.
    var onAboutTap: () -> Void = {}
    /// Opens the lesson index.
    var onLessonsTap: () -> Void = {}

    // Section expand/collapse state
    @State private var openGeometry = true
    @State private var openDisk = true
    @State private var openBloom = false
    @State private var openCamera = true
    @State private var openEffects = false
    @State private var openTools = true
    @State private var openScenarios = true

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    var body: some View {
        // Fit the panel to its content when the window is tall enough;
        // otherwise scroll inside the panel instead of overflowing the
        // window (the cause of the clipped / overlapped text in review).
        ViewThatFits(in: .vertical) {
            panelContent
            ScrollView(.vertical, showsIndicators: false) { panelContent }
        }
        .padding(14)
        .frame(width: 290)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 6)
        .colorScheme(.dark)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            qualityPicker

            section(title: "Scenarios", isOpen: $openScenarios) {
                ForEach(Scenario.free) { sc in
                    scenarioCard(sc)
                }
                Text(subscription.isProUnlocked ? "PRO SCENARIOS" : "PRO SCENARIOS (UNLOCK WITH PRO)")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 2)
                ForEach(Scenario.pro) { sc in
                    scenarioCard(sc)
                }
            }

            section(title: "Geometry", isOpen: $openGeometry) {
                slider("Mass",       value: $params.mass,            range: 0.1...10.0, format: "%.2f", unit: "M☉")
                slider("Spin",       value: $params.spin,            range: -0.99...0.99, format: "%.2f", unit: "a*")
                slider("Lensing",    value: $params.lensingStrength, range: 0.0...2.0,  format: "%.2f", unit: "η")
                slider("Frame drag", value: $params.frameDragStrength, range: 0.0...2.0, format: "%.2f", unit: "")
            }

            section(title: "Accretion disk", isOpen: $openDisk) {
                slider("Size",         value: $params.diskSize,        range: 4.0...100.0, format: "%.1f", unit: "M")
                slider("Density",      value: $params.diskDensity,     range: 0.0...5.0,  format: "%.2f", unit: "")
                slider("Temperature",  value: $params.diskTemp,        range: 1000.0...50000.0, format: "%.0f", unit: "K")
                slider("Scale height", value: $params.diskScaleHeight, range: 0.01...0.30, format: "%.2f", unit: "H/R")
                slider("Rotation speed", value: $params.diskSpeed,   range: 0.0...4.0,  format: "%.2f", unit: "x")
            }

            section(title: "Bloom", isOpen: $openBloom) {
                slider("Threshold", value: $params.bloomThreshold, range: 0.2...3.0, format: "%.2f", unit: "")
                slider("Intensity", value: $params.bloomIntensity, range: 0.0...1.5, format: "%.2f", unit: "")
            }

            section(title: "Camera", isOpen: $openCamera) {
                slider("Zoom",      value: $params.zoom,     range: 1.5...100.0, format: "%.1f", unit: "M")
                slider("Auto-spin", value: $params.autoSpin, range: -0.1...0.1,  format: "%.3f", unit: "rad/s")
            }

            section(title: "Tools", isOpen: $openTools) {
                toolButton(
                    label: "Lessons",
                    sub: subscription.isProUnlocked ? "8 guided physics tours" : "2 free, 6 more with Pro",
                    icon: "graduationcap",
                    locked: false
                ) { onLessonsTap() }

                if let onLiveWallpaperToggle = onLiveWallpaperToggle {
                    toolButton(
                        label: liveWallpaperActive ? "Stop Live Wallpaper" : "Set as Live Wallpaper",
                        sub: liveWallpaperActive
                             ? "Currently rendering on your desktop"
                             : "Renders behind windows + desktop icons",
                        icon: liveWallpaperActive ? "stop.circle" : "rectangle.on.rectangle",
                        locked: !subscription.isProUnlocked && !liveWallpaperActive
                    ) { onLiveWallpaperToggle() }
                }

                toolButton(
                    label: "Pomodoro",
                    sub: pomodoroSubtitle,
                    icon: "timer",
                    locked: !subscription.isProUnlocked
                ) {
                    if subscription.isProUnlocked {
                        onPomodoroTap()
                    } else {
                        subscription.showPaywall("The focus timer")
                    }
                }

                if let onWallpaperSaveTap = onWallpaperSaveTap {
                    toolButton(
                        label: "Save and Export",
                        sub: subscription.isProUnlocked ? "Screen frame, 4K poster, orbit video" : "Screen frame free; 4K and video with Pro",
                        icon: "square.and.arrow.down",
                        locked: false
                    ) { onWallpaperSaveTap() }
                }
            }

            section(title: "Effects", isOpen: $openEffects) {
                FlowToggleGrid(items: [
                    ("Lensing",  $params.enableLensing),
                    ("Disk",     $params.enableDisk),
                    ("Doppler",  $params.enableDoppler),
                    ("Photon",   $params.enablePhotonGlow),
                    ("Stars",    $params.enableStars),
                    ("Jets",     $params.enableJets),
                    ("Redshift", $params.showRedshift),
                ])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "hurricane")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(cyan)
            Text("KERR PARAMETERS")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            HStack(spacing: 6) {
                headerIconButton(symbol: "info") {
                    onAboutTap()
                }
                .help("About BlackHole")
                headerIconButton(symbol: "arrow.counterclockwise") {
                    withAnimation(.easeInOut(duration: 0.15)) { resetToDefaults() }
                }
                .help("Reset to defaults")
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func headerIconButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.65))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private var qualityPicker: some View {
        // Custom segmented control. Native Picker(.segmented) styling is fine
        // but the cyan accent fits the rest of the chrome better.
        HStack(spacing: 4) {
            ForEach(QualityPreset.allCases) { p in
                Button {
                    if p.isPro && !subscription.isProUnlocked {
                        subscription.showPaywall(p == .cinematic ? "Cinematic ray tracing" : "Ultra quality")
                    } else {
                        params.preset = p
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(p.shortName.uppercased())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if p.isPro && !subscription.isProUnlocked {
                            Image(systemName: "lock").font(.system(size: 7, weight: .bold))
                        }
                    }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(params.preset == p ? .black : .white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(params.preset == p ? cyan : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    params.preset == p ? Color.clear : Color.white.opacity(0.10),
                                    lineWidth: 0.6
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.30))
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        isOpen: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isOpen.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(cyan.opacity(0.85))
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                        .foregroundColor(cyan.opacity(0.85))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }

            sectionDivider
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }

    // MARK: - Slider row

    @ViewBuilder
    private func slider(_ label: String,
                        value: Binding<Float>,
                        range: ClosedRange<Float>,
                        format: String,
                        unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                Spacer()
                ValueChip(format: format, unit: unit, value: value.wrappedValue)
            }
            Slider(value: value, in: range)
                .tint(cyan)
        }
    }

    // MARK: - Reset

    /// Wipes every persisted setting (params + Pomodoro durations + Pomodoro
    /// session count). Cosmetic toggles like the dev-Pro override and any
    /// in-flight subscription state are deliberately preserved.
    private func resetToDefaults() {
        // Pomodoro back to factory durations + clear stats.
        pomodoro.workMinutes = 25
        pomodoro.shortBreakMinutes = 5
        pomodoro.longBreakMinutes = 15
        pomodoro.sessionsBeforeLongBreak = 4
        pomodoro.reset()
        params.resetToDefaults()
    }

    // MARK: - Tools section helpers

    @ViewBuilder
    private func toolButton(label: String,
                            sub: String,
                            icon: String,
                            locked: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(cyan.opacity(0.85))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                        if locked { ProBadge() }
                    }
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: locked ? "lock" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private var pomodoroSubtitle: String {
        if pomodoro.phase == .idle { return "Focus timer | 25 min default" }
        return "\(pomodoro.phase.label) | \(pomodoro.formattedTime)"
    }

    @ViewBuilder
    private func scenarioCard(_ sc: Scenario) -> some View {
        let locked = sc.isPro && !subscription.isProUnlocked
        return Button {
            if locked {
                subscription.showPaywall("The \(sc.displayName) scenario")
            } else {
                sc.apply(to: params)
                params.clampPreset(proUnlocked: subscription.isProUnlocked)
                subscription.noteMoment(.scenario)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sc.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(cyan.opacity(0.85))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(sc.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                        if locked { ProBadge() }
                    }
                    Text(sc.subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: locked ? "lock" : "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sub-components

private struct ValueChip: View {
    let format: String
    let unit: String
    let value: Float
    var body: some View {
        HStack(spacing: 4) {
            Text(String(format: format, value))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous).fill(Color.white.opacity(0.05))
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
        )
    }
}

/// Pill-style toggles laid out in a 2-column flow grid. Replaces the stack of
/// system Toggles for a denser, more "panel" feel.
private struct FlowToggleGrid: View {
    let items: [(String, Binding<Bool>)]

    private let cyan = Color(red: 0.55, green: 0.95, blue: 1.0)

    private var rows: [[(String, Binding<Bool>)]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { rIdx in
                HStack(spacing: 6) {
                    ForEach(rows[rIdx].indices, id: \.self) { cIdx in
                        let (label, binding) = rows[rIdx][cIdx]
                        TogglePill(label: label, isOn: binding, accent: cyan)
                    }
                    if rows[rIdx].count == 1 { Spacer().frame(maxWidth: .infinity) }
                }
            }
        }
    }
}

private struct TogglePill: View {
    let label: String
    @Binding var isOn: Bool
    let accent: Color

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(accent)
                    .opacity(isOn ? 1 : 0)
                    .frame(width: 9)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(isOn ? .white : .white.opacity(0.55))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? accent.opacity(0.16) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? accent.opacity(0.40) : Color.white.opacity(0.10), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }
}
