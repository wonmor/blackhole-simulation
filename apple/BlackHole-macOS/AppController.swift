import AppKit
import Combine
import SwiftUI

enum AppMode {
    case windowed
    case wallpaper
}

/// App-level state for macOS: switches between the windowed simulator and
/// the live-wallpaper mode. Owns the `WallpaperManager` and orchestrates
/// the 90-second free-preview hybrid paywall flow.
///
///   * Pro user                       → wallpaper mode permitted indefinitely
///   * Free user, preview .available  → 90s preview, then auto-expire to paywall
///   * Free user, preview .expired    → paywall sheet immediately
///
/// It also owns "bring the simulator window back": the app keeps running
/// from the menu bar after its window is closed, so every menu action that
/// needs a window host (sheets, paywall) goes through `showMainWindow`.
@MainActor
final class AppController: ObservableObject {

    @Published private(set) var mode: AppMode = .windowed

    let wallpaper: WallpaperManager
    private var cancellables = Set<AnyCancellable>()

    /// Re-opens the `Window("main")` scene. Set by `ContentView` from
    /// `@Environment(\.openWindow)`; menu-bar callers may also pass their own
    /// `OpenWindowAction` to `showMainWindow(using:)`.
    var openMainWindow: (() -> Void)?

    private weak var params: BlackHoleParameters?
    private weak var subscription: SubscriptionManager?

    init() {
        self.wallpaper = WallpaperManager()
    }

    /// Forwards subscription state changes (preview expiry) into mode changes.
    /// Idempotent — safe to call from `.task` even if SwiftUI re-fires it.
    func bind(subscription: SubscriptionManager, params: BlackHoleParameters) {
        self.params = params
        self.subscription = subscription
        cancellables.removeAll()
        subscription.$previewState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self = self else { return }
                if state == .expired && self.mode == .wallpaper {
                    self.wallpaper.markPreviewExpired()
                    // Clicking the wallpaper now exits to windowed + paywall.
                    self.wallpaper.onExpiredClick = { [weak self] in
                        Task { @MainActor in
                            guard let self = self else { return }
                            self.setMode(.windowed)
                            self.requestPaywall()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Mode switching

    func setMode(_ newMode: AppMode) {
        if newMode == mode { return }
        guard let params = params, let subscription = subscription else { return }

        if newMode == .wallpaper {
            if !subscription.isProUnlocked {
                switch subscription.previewState {
                case .available:
                    subscription.startPreview()
                case .running:
                    break
                case .expired:
                    requestPaywall()
                    return
                }
            }
            mode = .wallpaper
            wallpaper.start(params: params, subscription: subscription)
            hideMainWindows()
        } else {
            mode = .windowed
            wallpaper.stop()
            showMainWindow()
        }
    }

    /// Compatibility entry points used by `ContentView` / `MenuBarContent`.
    func setMode(_ newMode: AppMode,
                 params: BlackHoleParameters,
                 subscription: SubscriptionManager) {
        if self.params == nil || self.subscription == nil {
            bind(subscription: subscription, params: params)
        }
        setMode(newMode)
    }

    func toggleMode(params: BlackHoleParameters, subscription: SubscriptionManager) {
        setMode(mode == .windowed ? .wallpaper : .windowed,
                params: params, subscription: subscription)
    }

    /// Shows the paywall on the main window, re-opening the window first.
    func requestPaywall() {
        showMainWindow()
        subscription?.requestPaywall = true
    }

    // MARK: - Main window plumbing

    /// Brings the simulator window to the front, leaving wallpaper mode if
    /// needed and re-creating the window if the user closed it.
    func showMainWindow(using open: OpenWindowAction? = nil) {
        if mode == .wallpaper {
            mode = .windowed
            wallpaper.stop()
        }
        var anyShown = false
        for window in NSApplication.shared.windows where isUserWindow(window) {
            window.makeKeyAndOrderFront(nil)
            anyShown = true
        }
        if !anyShown {
            if let open = open {
                open(id: "main")
            } else {
                openMainWindow?()
            }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func hideMainWindows() {
        for window in NSApplication.shared.windows where isUserWindow(window) {
            window.orderOut(nil)
        }
    }

    /// True when a simulator window is on screen.
    var isMainWindowVisible: Bool {
        NSApplication.shared.windows.contains { isUserWindow($0) && $0.isVisible }
    }

    private func isUserWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeMain else { return false }
        if window.title == "BlackHole Wallpaper" { return false }
        return window.contentViewController != nil || window.contentView != nil
    }
}
