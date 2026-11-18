import SwiftUI

/// The iBlackHole window on Apple Vision Pro: open the black hole in your room
/// or in full immersion, then tune the spacetime and the disk while you look at it.
struct VisionControlsView: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject private var control = ImmersiveController.shared

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var busy = false
    @State private var showPomodoro = false
    @State private var showAbout = false
    @State private var sizeValue: Float = 1.0
    @State private var didLaunchArgs = false

    private let accent = Color(red: 1.0, green: 0.62, blue: 0.30)

    var body: some View {
        NavigationStack {
            Form {
                Section { hero }
                Section { spaceButtons } footer: { Text(gestureHint) }
                if control.isOpen { Section("In the room") { placementControls } }
                Section("Scenarios") { scenarios }
                Section("Black hole") { blackHoleSliders }
                Section("Accretion disk") { diskSliders }
                Section("Effects") { effects }
                Section("Ray tracing quality") { quality }
                Section("More") { more }
            }
            .navigationTitle("iBlackHole")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About iBlackHole")
                }
            }
        }
        .sheet(isPresented: $showPomodoro) { PomodoroView(timer: pomodoro).frame(width: 460, height: 560) }
        .sheet(isPresented: $showAbout) { AboutSheet().frame(width: 620, height: 760) }
        .onChange(of: subscription.previewState) { _, state in
            // The free look at full immersion ended: drop back into the room.
            if state == .expired, control.mode == .space, !subscription.isProUnlocked {
                control.setMode(.room)
                subscription.showPaywall("Full immersion")
            }
        }
        .task { await applyLaunchArguments() }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 18) {
            Image("BrandMark")
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("A rotating black hole, ray traced live")
                    .font(.title3.weight(.semibold))
                Text("Every pixel in each eye is a light ray followed through Kerr spacetime: the shadow, the photon ring and the lensed, Doppler-beamed accretion disk are computed as you watch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Space buttons

    private var spaceButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                spaceButton(.room, title: "In Your Room", sub: "Floats in front of you", icon: "cube.transparent")
                spaceButton(.space, title: "Full Immersion",
                            sub: subscription.isProUnlocked ? "Lensed stars all around"
                                 : (subscription.previewState == .expired ? "Pro" : "Free 90 s preview, then Pro"),
                            icon: "sparkles")
            }
            if control.isOpen {
                Button(role: .destructive) {
                    Task { busy = true; await dismissImmersiveSpace(); busy = false }
                } label: {
                    Label("Leave", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .disabled(busy)
            }
        }
        .padding(.vertical, 4)
    }

    private func spaceButton(_ mode: SpaceMode, title: String, sub: String, icon: String) -> some View {
        let active = control.isOpen && control.mode == mode
        let locked = mode == .space && !subscription.isProUnlocked && subscription.previewState == .expired
        return Button {
            Task { await open(mode) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).font(.title2)
                    Spacer()
                    if locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                    else if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                }
                Text(title).font(.headline)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(active ? accent : nil)
        .disabled(busy)
    }

    private var gestureHint: String {
        "Look at the black hole, pinch and drag to orbit it. Pinch with both hands and pull them apart to make it bigger. The Digital Crown or Leave returns you to your space."
    }

    @MainActor
    private func open(_ mode: SpaceMode) async {
        if mode == .space && !subscription.isProUnlocked {
            switch subscription.previewState {
            case .available: subscription.startPreview()
            case .running: break
            case .expired:
                subscription.showPaywall("Full immersion")
                return
            }
        }
        control.setMode(mode)
        guard !control.isOpen else { return }
        busy = true
        control.requestRecenter()
        let result = await openImmersiveSpace(id: "blackhole-immersive")
        if case .opened = result { control.isOpen = true }
        busy = false
    }

    // MARK: - Placement

    @ViewBuilder
    private var placementControls: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Size")
                Spacer()
                Text(String(format: "%.0f cm disk", 110 * sizeValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $sizeValue, in: 0.35...3.0)
                .onChange(of: sizeValue) { _, v in control.size = v }
        }
        HStack {
            Button { control.requestRecenter() } label: { Label("Bring in Front of Me", systemImage: "scope") }
            Spacer()
            Button { control.resetOrientation() } label: { Label("Reset Orbit", systemImage: "arrow.counterclockwise") }
        }
        .buttonStyle(.bordered)
        if control.fps > 0 {
            LabeledContent("Frame rate", value: String(format: "%.0f fps", control.fps))
        }
    }

    // MARK: - Scenarios

    private var scenarios: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Scenario.allCases) { sc in
                let locked = sc.isPro && !subscription.isProUnlocked
                Button {
                    if locked { subscription.showPaywall("The \(sc.displayName) scenario"); return }
                    sc.apply(to: params)
                    params.clampPreset(proUnlocked: subscription.isProUnlocked)
                    control.resetOrientation()
                    subscription.noteMoment(.scenario)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sc.symbol).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sc.displayName).font(.subheadline.weight(.semibold))
                            Text(sc.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Sliders

    @ViewBuilder
    private var blackHoleSliders: some View {
        slider("Spin", $params.spin, -0.99...0.99, "%.2f a*")
        slider("Lensing", $params.lensingStrength, 0...2, "%.2f")
        slider("Frame dragging", $params.frameDragStrength, 0...2, "%.2f")
    }

    @ViewBuilder
    private var diskSliders: some View {
        slider("Temperature", $params.diskTemp, 1000...50000, "%.0f K")
        slider("Density", $params.diskDensity, 0...5, "%.2f")
        slider("Extent", $params.diskSize, 20...75, "%.0f M")
        slider("Thickness", $params.diskScaleHeight, 0.01...0.30, "%.2f H/R")
        slider("Rotation speed", $params.diskSpeed, 0...4, "%.2fx")
    }

    private func slider(_ title: String, _ value: Binding<Float>, _ range: ClosedRange<Float>, _ fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: fmt, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    @ViewBuilder
    private var effects: some View {
        Toggle("Accretion disk", isOn: $params.enableDisk)
        Toggle("Gravitational lensing", isOn: $params.enableLensing)
        Toggle("Doppler beaming", isOn: $params.enableDoppler)
        Toggle("Photon ring", isOn: $params.enablePhotonGlow)
        Toggle("Relativistic jets", isOn: $params.enableJets)
        Toggle("Lensed stars (Full Immersion)", isOn: $params.enableStars)
    }

    private var quality: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Quality", selection: Binding(
                get: { params.preset },
                set: { p in
                    if p.isPro && !subscription.isProUnlocked {
                        subscription.showPaywall(p == .cinematic ? "Cinematic ray tracing" : "Ultra quality")
                    } else {
                        params.preset = p
                    }
                })) {
                ForEach(QualityPreset.allCases, id: \.self) { p in
                    Text(p.isPro && !subscription.isProUnlocked ? "\(p.displayName) (Pro)" : p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            Text("Higher settings follow each ray with more steps and render it sharper. The app lowers the internal resolution on its own if a frame would miss 90 fps.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - More

    @ViewBuilder
    private var more: some View {
        Button {
            subscription.showPaywall(nil)
        } label: {
            Label(subscription.isProUnlocked ? "iBlackHole Pro (Active)" : "iBlackHole Pro", systemImage: "star.circle")
        }
        Button {
            if subscription.isProUnlocked { showPomodoro = true } else { subscription.showPaywall("The focus timer") }
        } label: {
            HStack {
                Label("Focus Timer", systemImage: "timer")
                Spacer()
                if !subscription.isProUnlocked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
            }
        }
        Button { Task { await subscription.restore() } } label: {
            Label("Restore Purchases", systemImage: "arrow.clockwise")
        }
        Link(destination: AppLinks.privacyPolicy) { Label("Privacy Policy", systemImage: "hand.raised") }
        Link(destination: AppLinks.termsOfUse) { Label("Terms of Use (EULA)", systemImage: "doc.text") }
        Button { params.resetToDefaults(); control.resetOrientation(); sizeValue = 1; control.size = 1 } label: {
            Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
        }
    }

    // MARK: - Launch arguments (store screenshots and the frame-rate log)

    @MainActor
    private func applyLaunchArguments() async {
        guard !didLaunchArgs else { return }
        didLaunchArgs = true
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "bhScenario"), let sc = Scenario(rawValue: raw) {
            sc.apply(to: params)
            params.clampPreset(proUnlocked: subscription.isProUnlocked)
        }
        if let raw = d.string(forKey: "bhPreset"), let pr = QualityPreset(rawValue: raw) {
            params.preset = pr
            params.clampPreset(proUnlocked: subscription.isProUnlocked)
        }
        if d.object(forKey: "bhSize") != nil { sizeValue = d.float(forKey: "bhSize"); control.size = sizeValue }
        if d.object(forKey: "bhYaw") != nil || d.object(forKey: "bhTilt") != nil {
            control.resetOrientation()
            control.orbit(dYaw: d.float(forKey: "bhYaw"), dTilt: d.float(forKey: "bhTilt"))
        }
        if d.bool(forKey: "bhPaywall") { subscription.showPaywall(nil) }
        if let m = d.string(forKey: "bhSpace"), let mode = SpaceMode(rawValue: m) {
            try? await Task.sleep(for: .seconds(1.5))
            await open(mode)
            if d.bool(forKey: "bhSolo") {
                try? await Task.sleep(for: .seconds(2))
                dismissWindow(id: "control")
            }
        }
    }
}
