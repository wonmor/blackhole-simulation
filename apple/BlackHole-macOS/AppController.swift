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
@MainActor
final class AppController: ObservableObject {

    @Published private(set) var mode: AppMode = .windowed
    @Published var showAbout: Bool = false

    let wallpaper: WallpaperManager
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.wallpaper = WallpaperManager()
    }

    /// Forwards subscription state changes (preview expiry) into mode changes.
    /// Idempotent — safe to call from `.task` even if SwiftUI re-fires it.
    func bind(subscription: SubscriptionManager, params: BlackHoleParameters) {
        cancellables.removeAll()
        subscription.$previewState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self = self else { return }
                if state == .expired && self.mode == .wallpaper {
                    self.wallpaper.markPreviewExpired()
                    // Clicking the wallpaper now exits to windowed + paywall.
                    self.wallpaper.onExpiredClick = { [weak subscription, weak self] in
                        Task { @MainActor in
                            self?.setMode(.windowed,
                                          params: params,
                                          subscription: subscription ?? SubscriptionManager())
                            subscription?.requestPaywall = true
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    func setMode(_ newMode: AppMode,
                 params: BlackHoleParameters,
                 subscription: SubscriptionManager) {
        if newMode == mode { return }

        if newMode == .wallpaper {
            if !subscription.isProUnlocked {
                switch subscription.previewState {
                case .available:
                    subscription.startPreview()
                case .running:
                    break
                case .expired:
                    subscription.requestPaywall = true
                    return
                }
            }
            mode = .wallpaper
            wallpaper.start(params: params, subscription: subscription)
            hideMainWindows()
        } else {
            mode = .windowed
            wallpaper.stop()
            showMainWindows()
        }
    }

    func toggleMode(params: BlackHoleParameters, subscription: SubscriptionManager) {
        setMode(mode == .windowed ? .wallpaper : .windowed,
                params: params, subscription: subscription)
    }

    // MARK: - Main window plumbing

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
        if !anyShown {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func isUserWindow(_ window: NSWindow) -> Bool {
        guard window.canBecomeMain else { return false }
        if window.title == "BlackHole Wallpaper" { return false }
        return window.contentViewController != nil || window.contentView != nil
    }
}
