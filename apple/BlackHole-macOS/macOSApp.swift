import SwiftUI

@main
struct BlackHoleMacApp: App {
    @StateObject private var params       = BlackHoleParameters()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var controller   = AppController()
    @StateObject private var pomodoro     = PomodoroTimer()
    @StateObject private var ui           = UIState()

    var body: some Scene {
        // A single simulator window (not a WindowGroup): "Show Simulator
        // Window" from the menu bar always brings this one back instead of
        // spawning a second Metal renderer.
        Window("BlackHole", id: "main") {
            ContentView(params: params,
                        subscription: subscription,
                        pomodoro: pomodoro,
                        ui: ui)
                .preferredColorScheme(.dark)
                // Smallest window every layout is checked at: the HUD with
                // equations, the control panel and the lesson card fit side by
                // side, panels scroll, and sheets cap to the window height.
                .frame(minWidth: 900, minHeight: 620)
                .environmentObject(controller)
                .environmentObject(subscription)
                .task {
                    controller.bind(subscription: subscription, params: params)
                }
                #if DEBUG
                .task { await QALaunch.apply(params: params, ui: ui, subscription: subscription) }
                #endif
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            BlackHoleCommands(params: params,
                              subscription: subscription,
                              controller: controller,
                              pomodoro: pomodoro,
                              ui: ui)
        }

        MenuBarExtra("BlackHole", systemImage: "circle.dashed") {
            MenuBarContent(
                params: params,
                controller: controller,
                subscription: subscription,
                pomodoro: pomodoro,
                ui: ui
            )
        }
    }
}

/// Main-menu commands. Every item is wired to the same state objects the
/// window uses, so the menu bar does exactly what the on-screen buttons do.
struct BlackHoleCommands: Commands {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var controller: AppController
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject var ui: UIState

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // BlackHole ▸ About
        CommandGroup(replacing: .appInfo) {
            Button("About BlackHole") { present { ui.showAbout = true } }
        }

        // File ▸ (no documents; replace New with the window re-opener)
        CommandGroup(replacing: .newItem) {
            Button("Show Simulator Window") { controller.showMainWindow(using: openWindow) }
                .keyboardShortcut("1", modifiers: .command)
        }

        // View ▸ panels
        CommandGroup(before: .toolbar) {
            Toggle("Show Controls Panel", isOn: $ui.showControls)
                .keyboardShortcut("k", modifiers: .command)
            Toggle("Show Equations", isOn: $ui.showEquations)
                .keyboardShortcut("e", modifiers: .command)
            Divider()
        }

        CommandMenu("Simulation") {
            Picker("Quality", selection: $params.preset) {
                ForEach(QualityPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            Menu("Load Scenario") {
                ForEach(Scenario.allCases) { scenario in
                    Button(scenario.displayName) { scenario.apply(to: params) }
                }
            }
            Divider()
            Toggle("Gravitational Lensing", isOn: $params.enableLensing)
            Toggle("Accretion Disk", isOn: $params.enableDisk)
            Toggle("Doppler Boost", isOn: $params.enableDoppler)
            Toggle("Photon-Sphere Glow", isOn: $params.enablePhotonGlow)
            Toggle("Relativistic Jets", isOn: $params.enableJets)
            Toggle("Starfield", isOn: $params.enableStars)
            Toggle("Redshift Overlay", isOn: $params.showRedshift)
            Divider()
            Button("Reset to Defaults") { params.resetToDefaults() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("Pro") {
            Button(controller.mode == .wallpaper ? "Stop Live Wallpaper" : "Set as Live Wallpaper") {
                controller.toggleMode(params: params, subscription: subscription)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button("Pomodoro Timer…") {
                present {
                    if subscription.isProUnlocked { ui.showPomodoro = true }
                    else { subscription.requestPaywall = true }
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Divider()

            if subscription.isProUnlocked {
                Button("Manage Subscription…") { NSWorkspace.shared.open(AppLinks.manageSubscriptions) }
            } else {
                Button("Subscribe to BlackHole Pro…") { present { subscription.requestPaywall = true } }
            }
            Button("Restore Purchases") { Task { await subscription.restore() } }
        }

        // Help ▸ real destinations instead of the empty default help book
        CommandGroup(replacing: .help) {
            Button("What is BlackHole?") { present { ui.showWelcome = true } }
            Divider()
            Button("Physics Notes & References") { NSWorkspace.shared.open(AppLinks.physicsNotes) }
            Button("Support (GitHub)") { NSWorkspace.shared.open(AppLinks.support) }
            Divider()
            Button("Privacy Policy") { NSWorkspace.shared.open(AppLinks.privacyPolicy) }
            Button("Terms of Use (Apple Standard EULA)") { NSWorkspace.shared.open(AppLinks.termsOfUse) }
        }
    }

    /// Sheets need the simulator window as a host; make sure it is up first.
    private func present(_ action: @escaping () -> Void) {
        controller.showMainWindow(using: openWindow)
        // Let the window materialise before the sheet is requested.
        DispatchQueue.main.async(execute: action)
    }
}
