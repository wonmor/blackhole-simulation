import SwiftUI

@main
struct BlackHoleiOSApp: App {
    @StateObject private var params = BlackHoleParameters()

    var body: some Scene {
        WindowGroup {
            ContentView(params: params)
                .preferredColorScheme(.dark)
                .ignoresSafeArea()
        }
    }
}
