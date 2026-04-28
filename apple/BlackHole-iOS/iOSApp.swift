import SwiftUI

@main
struct BlackHoleiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .ignoresSafeArea()
        }
    }
}
