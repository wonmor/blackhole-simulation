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
                .task { await QALaunch.apply(params: params, ui: ui, subscription: subscription) }
                #endif
        }
    }

}
