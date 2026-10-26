import SwiftUI

@main
struct BlackHoleiOSApp: App {
    @StateObject private var params       = BlackHoleParameters()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var pomodoro     = PomodoroTimer()
    @StateObject private var ui           = UIState()

    var body: some Scene {
        WindowGroup {
            ContentView(params: params,
                        subscription: subscription,
                        pomodoro: pomodoro,
                        ui: ui)
                .preferredColorScheme(.dark)
                // NOTE: .ignoresSafeArea() is applied INSIDE ContentView (on the
                // MetalView only) so the foreground HUD + ControlPanel respect
                // the iPhone's notch / Dynamic Island / status bar.
                #if DEBUG
                .task { await qaLaunchArgs() }
                #endif
        }
    }

    #if DEBUG
    /// Simulator QA / screenshot hooks. Debug builds only.
    @MainActor
    private func qaLaunchArgs() async {
        let args = ProcessInfo.processInfo.arguments
        func value(_ k: String) -> String? {
            guard let i = args.firstIndex(of: k), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("-bhSkipWelcome") { ui.markWelcomeSeen() }
        if let n = value("-bhScenario"), let sc = Scenario(rawValue: n) { sc.apply(to: params) }
        if let q = value("-bhPreset"), let p = QualityPreset(rawValue: q) { params.preset = p }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if let n = value("-bhLesson"), let i = Int(n), let l = Lesson(rawValue: i) {
            l.apply(to: params); ui.activeLesson = l
        }
        if args.contains("-bhShowControls") { ui.showControls = true }
        if args.contains("-bhShowLessons") { ui.showLessons = true }
        if args.contains("-bhShowExport") { ui.showExport = true }
        if args.contains("-bhShowPaywall") { subscription.showPaywall(value("-bhPaywallReason")) }
    }
    #endif
}
