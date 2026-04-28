import SwiftUI

/// Menu-bar dropdown content. The menu is always present; the wallpaper
/// toggle is gated behind `subscription.isProUnlocked`.
struct MenuBarContent: View {
    @ObservedObject var params: BlackHoleParameters
    @ObservedObject var controller: AppController
    @ObservedObject var subscription: SubscriptionManager

    var body: some View {
        // Mode
        Button(controller.mode == .wallpaper
               ? "Stop Live Wallpaper"
               : (subscription.isProUnlocked ? "Set as Live Wallpaper" : "Set as Live Wallpaper · Pro")) {
            controller.toggleMode(params: params, subscription: subscription)
        }
        .keyboardShortcut("L", modifiers: [.command, .option])

        Button(controller.mode == .windowed ? "Hide Window" : "Show Window") {
            controller.setMode(controller.mode == .windowed ? .wallpaper : .windowed,
                               params: params, subscription: subscription)
        }
        .disabled(controller.mode == .wallpaper)  // can't show during wallpaper

        Divider()

        // Quality
        Menu("Quality") {
            ForEach(QualityPreset.allCases) { preset in
                Button {
                    params.preset = preset
                } label: {
                    HStack {
                        Text(preset.displayName)
                        if params.preset == preset {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        // Subscription
        if subscription.isProUnlocked {
            Button("Manage Subscription…") {
                if let url = URL(string: "macappstore://apps.apple.com/account/subscriptions") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            Button("Subscribe to Pro…") {
                controller.requestPaywall = true
            }
        }

        // Debug toggle (visible in DEBUG builds via the Option key — discoverable
        // without cluttering production menus).
        #if DEBUG
        Divider()
        Button(subscription.isProUnlocked ? "DEV · Lock Pro" : "DEV · Unlock Pro") {
            subscription.toggleDevOverride()
        }
        #endif

        Divider()

        Button("About BlackHole") {
            controller.showAbout = true
        }
        Button("Quit BlackHole") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
