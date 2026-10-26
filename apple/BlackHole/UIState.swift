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
    static let support = URL(string: "https://github.com/wonmor/blackhole-simulation")!
    static let physicsNotes = URL(string: "https://github.com/wonmor/blackhole-simulation/blob/main/docs/PHYSICS.md")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}
