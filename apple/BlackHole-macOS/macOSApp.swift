import SwiftUI

@main
struct BlackHoleMacApp: App {
    @StateObject private var params       = BlackHoleParameters()
    @StateObject private var subscription = SubscriptionManager()
    @StateObject private var controller   = AppController()
    @StateObject private var pomodoro     = PomodoroTimer()

    /// Bridges the menu-bar Pomodoro tap into the windowed scene's sheet.
    @State private var pomodoroRequested = false

    var body: some Scene {
        WindowGroup("BlackHole", id: "main") {
            ContentView(params: params,
                        subscription: subscription,
                        pomodoro: pomodoro)
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(controller)
                .environmentObject(subscription)
                .task {
                    controller.bind(subscription: subscription, params: params)
                }
                .sheet(isPresented: $pomodoroRequested) {
                    PomodoroView(timer: pomodoro)
                        .padding(.horizontal, 8)
                }
                .sheet(isPresented: $controller.showAbout) {
                    AboutSheet()
                        .padding(.horizontal, 8)
                }
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("BlackHole", systemImage: "circle.dashed") {
            MenuBarContent(
                params: params,
                controller: controller,
                subscription: subscription,
                pomodoro: pomodoro,
                onPomodoroTap: { pomodoroRequested = true }
            )
        }
    }
}
