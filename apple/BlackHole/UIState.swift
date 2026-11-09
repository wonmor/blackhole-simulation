import Foundation
import Combine

/// Cross-platform presentation state shared by the main window, the macOS
/// main menu (`.commands`), and the macOS menu-bar extra. Keeping it in one
/// observable object (instead of `@State` inside `ContentView`) is what lets
/// a menu item anywhere in the app open the same sheet the toolbar buttons
/// open.
@MainActor
final class UIState: ObservableObject {
    @Published var showControls: Bool = false
    @Published var showPomodoro: Bool = false
    @Published var showAbout: Bool = false
    @Published var showWelcome: Bool = false
    /// Expands the equation list inside the HUD.
    @Published var showEquations: Bool = false
    /// Lesson index sheet.
    @Published var showLessons: Bool = false
    /// Lesson whose card is shown over the simulation (nil = none).
    @Published var activeLesson: Lesson? = nil
    /// Pro export sheet (4K poster, orbit video). iOS only.
    @Published var showExport: Bool = false

    private static let welcomeSeenKey = "bh.hasSeenWelcome"

    init() {
        showWelcome = !UserDefaults.standard.bool(forKey: Self.welcomeSeenKey)
    }

    func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: Self.welcomeSeenKey)
        showWelcome = false
    }
}

/// Every outbound link the app shows, in one place so the paywall, About
/// sheet, and macOS Help menu can never drift apart.
enum AppLinks {
    /// Apple's standard EULA. The app ships no custom Terms of Use, so this is
    /// the licence agreement that governs it (App Review Guideline 3.1.2).
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Dedicated BlackHole privacy policy (GitHub Pages render of PRIVACY.md).
    static let privacyPolicy = URL(string: "https://wonmor.github.io/blackhole-simulation/privacy")!
    static let support = URL(string: "https://wonmor.github.io/blackhole-simulation/support/")!
    static let physicsNotes = URL(string: "https://wonmor.github.io/blackhole-simulation/physics/")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

import SwiftUI

private struct SheetMaxHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 10_000
}

extension EnvironmentValues {
    /// Tallest a sheet may be (macOS: the host window's content height minus
    /// a margin). Sheets scroll inside this instead of being cut off.
    var sheetMaxHeight: CGFloat {
        get { self[SheetMaxHeightKey.self] }
        set { self[SheetMaxHeightKey.self] = newValue }
    }
}

extension View {
    /// Fades the bottom edge of a scrolling panel so clipped content reads as
    /// "scroll for more" rather than as text cut off by the window.
    func scrollFadeMask() -> some View {
        mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
            }
        )
    }
}
