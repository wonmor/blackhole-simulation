import SwiftUI

/// Menu-bar (status item) dropdown. The app keeps running here after its
/// window is closed, so every item that needs a window first re-opens the
/// simulator window through `AppController.showMainWindow`.
struct MenuBarContent: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var controller: AppController
    @ObservedObject var subscription: SubscriptionManager
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject var ui: UIState

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Mode
        Button(wallpaperLabel) {
            controller.toggleMode(params: params, subscription: subscription)
        }
        .keyboardShortcut("l", modifiers: [.command, .option])

        Button("Show Simulator Window") {
            controller.showMainWindow(using: openWindow)
        }
        Button("Hide Simulator Window") {
            controller.hideMainWindows()
        }
        .disabled(controller.mode == .wallpaper)

        Divider()

        // Quality — Picker renders as a submenu with a checkmark on the
        // active preset.
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

        // Pomodoro
        Button(pomodoroLabel) {
            present {
                if subscription.isProUnlocked { ui.showPomodoro = true }
                else { subscription.requestPaywall = true }
            }
        }
        .keyboardShortcut("p", modifiers: [.command, .option])

        Divider()

        // Subscription
        if subscription.isProUnlocked {
            Button("Manage Subscription…") {
                NSWorkspace.shared.open(AppLinks.manageSubscriptions)
            }
        } else {
            Button("Subscribe to BlackHole Pro…") {
                present { subscription.requestPaywall = true }
            }
        }

        #if DEBUG
        Divider()
        Button(subscription.isProUnlocked ? "DEV: Lock Pro" : "DEV: Unlock Pro") {
            subscription.toggleDevOverride()
        }
        #endif

        Divider()

        Button("What is BlackHole?") { present { ui.showWelcome = true } }
        Button("About BlackHole") { present { ui.showAbout = true } }
        Button("Quit BlackHole") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func present(_ action: @escaping () -> Void) {
        controller.showMainWindow(using: openWindow)
        DispatchQueue.main.async(execute: action)
    }

    private var wallpaperLabel: String {
        if controller.mode == .wallpaper { return "Stop Live Wallpaper" }
        if subscription.isProUnlocked { return "Set as Live Wallpaper" }
        switch subscription.previewState {
        case .available: return "Try Live Wallpaper (90 s preview)"
        case .running:   return "Set as Live Wallpaper"
        case .expired:   return "Set as Live Wallpaper (Pro)…"
        }
    }

    private var pomodoroLabel: String {
        if pomodoro.phase == .idle { return subscription.isProUnlocked ? "Pomodoro Timer…" : "Pomodoro Timer (Pro)…" }
        return "Pomodoro | \(pomodoro.formattedTime) (\(pomodoro.phase.label))"
    }
}
