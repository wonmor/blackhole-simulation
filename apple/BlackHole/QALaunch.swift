import SwiftUI
#if os(macOS)
import AppKit
#endif

#if DEBUG
/// Simulator / local QA and store-screenshot hooks. Debug builds only.
@MainActor
enum QALaunch {
    static func apply(params: BlackHoleParameters, ui: UIState, subscription: SubscriptionManager) async {
        let args = ProcessInfo.processInfo.arguments
        func value(_ k: String) -> String? {
            guard let i = args.firstIndex(of: k), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("-bhSkipWelcome") { ui.markWelcomeSeen() }
        if let n = value("-bhScenario"), let sc = Scenario(rawValue: n) { sc.apply(to: params) }
        if let q = value("-bhPreset"), let p = QualityPreset(rawValue: q) { params.preset = p }
        if let z = value("-bhZoom"), let f = Float(z) { params.zoom = f }
        #if os(macOS)
        // -bhWindowSize 960x640 : resize the simulator window's content area.
        if let s = value("-bhWindowSize") {
            let parts = s.split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                for w in NSApp.windows where w.identifier?.rawValue.contains("main") == true || w.title == "BlackHole" {
                    w.setContentSize(NSSize(width: parts[0], height: parts[1]))
                    w.center()
                }
            }
        }
        #endif
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if let n = value("-bhLesson"), let i = Int(n), let l = Lesson(rawValue: i) {
            l.apply(to: params); ui.activeLesson = l
        }
        if args.contains("-bhShowControls") { ui.showControls = true }
        if args.contains("-bhShowEquations") { ui.showEquations = true }
        if args.contains("-bhShowLessons") { ui.showLessons = true }
        if args.contains("-bhShowAbout") { ui.showAbout = true }
        if args.contains("-bhShowPomodoro") { ui.showPomodoro = true }
        #if os(iOS)
        if args.contains("-bhShowExport") { ui.showExport = true }
        #endif
        if args.contains("-bhShowPaywall") { subscription.showPaywall(value("-bhPaywallReason")) }
    }
}
#endif
