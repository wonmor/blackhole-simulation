import Foundation

/// Vision Pro copy of the debug-only store-screenshot switch (HUDView.swift,
/// which defines it on iPhone and Mac, is not part of this target).
enum ScreenshotMode {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-bhScreenshotMode")
    #else
    static let isOn = false
    #endif
}
