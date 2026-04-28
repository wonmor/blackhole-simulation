import SwiftUI

@main
struct BlackHoleiOSApp: App {
    @StateObject private var params       = BlackHoleParameters()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var pomodoro     = PomodoroTimer()

    var body: some Scene {
        WindowGroup {
            ContentView(params: params,
                        subscription: subscription,
                        pomodoro: pomodoro)
                .preferredColorScheme(.dark)
                .ignoresSafeArea()
        }
    }
}
