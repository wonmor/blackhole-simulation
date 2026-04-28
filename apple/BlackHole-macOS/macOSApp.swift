import SwiftUI

@main
struct BlackHoleMacApp: App {
    @StateObject private var params       = BlackHoleParameters()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var controller   = AppController()

    var body: some Scene {
        // Primary windowed simulator. Hidden when entering wallpaper mode.
        WindowGroup("BlackHole", id: "main") {
            ContentView(params: params)
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(controller)
                .environmentObject(subscription)
                .sheet(isPresented: $controller.requestPaywall) {
                    PaywallSheet(subscription: subscription)
                }
        }
        .windowStyle(.hiddenTitleBar)

        // Always-on menu bar entry point.
        MenuBarExtra("BlackHole", systemImage: "circle.dashed") {
            MenuBarContent(params: params,
                           controller: controller,
                           subscription: subscription)
        }
    }
}
