import AppKit
import SwiftUI

enum AppMode {
    case windowed
    case wallpaper
}

/// App-level state for macOS: switches between the windowed simulator
/// and the live-wallpaper mode. Owns the `WallpaperManager`.
///
/// Subscription gating is enforced here — attempting to enter wallpaper
/// mode without `isProUnlocked` raises `requestPaywall = true`, which
/// the menu-bar UI uses to present the paywall sheet.
@MainActor
final class AppController: ObservableObject {

    @Published private(set) var mode: AppMode = .windowed
    @Published var requestPaywall: Bool = false
    @Published var showAbout: Bool = false

    let wallpaper: WallpaperManager

    init() {
        self.wallpaper = WallpaperManager()
    }

    func setMode(_ newMode: AppMode,
                 params: BlackHoleParameters,
                 subscription: SubscriptionManager) {
        if newMode == mode { return }
        if newMode == .wallpaper && !subscription.isProUnlocked {
            requestPaywall = true
            return
        }
        mode = newMode
        switch newMode {
        case .wallpaper:
            wallpaper.start(params: params)
            hideMainWindows()
        case .windowed:
            wallpaper.stop()
            showMainWindows()
        }
    }

    func toggleMode(params: BlackHoleParameters, subscription: SubscriptionManager) {
        setMode(mode == .windowed ? .wallpaper : .windowed,
                params: params, subscription: subscription)
    }

    // MARK: - Main window plumbing

    /// Heuristic: hide every visible NSWindow that the SwiftUI WindowGroup
    /// owns (titled, has a content controller, can become main). Skips
    /// wallpaper windows (we manage those separately) and menu-bar panels.
    private func hideMainWindows() {
        for window in NSApplication.shared.windows where isUserWindow(window) {
            window.orderOut(nil)
        }
    }

    private func showMainWindows() {
        var anyShown = false
        for window in NSApplication.shared.windows where isUserWindow(window) {
            window.makeKeyAndOrderFront(nil)
            anyShown = true
        }
        // If SwiftUI never created the window, ask AppKit to send the
        // standard "show main window" action — WindowGroup hooks it.
        if !anyShown {
            NSApplication.shared.sendAction(
                Selector(("showSwiftUIWindow:")), to: nil, from: nil
            )
        }
    }

    private func isUserWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeMain else { return false }
        if window.title == "BlackHole Wallpaper" { return false }
        return window.contentViewController != nil || window.contentView != nil
    }
}
