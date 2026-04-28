import Foundation
import Combine
import UserNotifications

/// Cross-platform Pomodoro state machine.
///
/// Phase cycle: .working → (.shortBreak | .longBreak) → .working → ...
/// Long break replaces a short break every `sessionsBeforeLongBreak` cycles.
/// Posts `UNUserNotificationCenter` local notifications on phase end so the
/// user gets a system-level cue even when the app is in the background.
@MainActor
final class PomodoroTimer: ObservableObject {

    enum Phase: String {
        case idle, working, shortBreak, longBreak
        var label: String {
            switch self {
            case .idle:       return "Ready"
            case .working:    return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak:  return "Long Break"
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var timeRemaining: TimeInterval = 25 * 60
    @Published private(set) var completedSessions: Int = 0
    @Published private(set) var isRunning: Bool = false

    // MARK: - Configurable durations (minutes, persisted)

    @Published var workMinutes: Int = 25 {
        didSet { UserDefaults.standard.set(workMinutes, forKey: "pomodoro_work_min")
                 if phase == .idle { timeRemaining = currentPhaseDuration() } }
    }
    @Published var shortBreakMinutes: Int = 5 {
        didSet { UserDefaults.standard.set(shortBreakMinutes, forKey: "pomodoro_short_min") }
    }
    @Published var longBreakMinutes: Int = 15 {
        didSet { UserDefaults.standard.set(longBreakMinutes, forKey: "pomodoro_long_min") }
    }
    @Published var sessionsBeforeLongBreak: Int = 4 {
        didSet { UserDefaults.standard.set(sessionsBeforeLongBreak, forKey: "pomodoro_long_every") }
    }

    // MARK: - Internals

    private var endDate: Date?
    private var timer: Timer?

    init() {
        let defaults = UserDefaults.standard
        if let v = defaults.object(forKey: "pomodoro_work_min") as? Int { workMinutes = v }
        if let v = defaults.object(forKey: "pomodoro_short_min") as? Int { shortBreakMinutes = v }
        if let v = defaults.object(forKey: "pomodoro_long_min") as? Int { longBreakMinutes = v }
        if let v = defaults.object(forKey: "pomodoro_long_every") as? Int { sessionsBeforeLongBreak = v }
        timeRemaining = TimeInterval(workMinutes) * 60
        Task { await requestNotificationPermission() }
    }

    deinit { timer?.invalidate() }

    // MARK: - Public API

    func start() {
        if phase == .idle {
            beginPhase(.working)
        } else if !isRunning {
            // Resume paused timer.
            endDate = Date().addingTimeInterval(timeRemaining)
            startTicker()
        }
    }

    func pause() {
        guard isRunning else { return }
        timer?.invalidate(); timer = nil
        if let end = endDate {
            timeRemaining = max(0, end.timeIntervalSinceNow)
        }
        endDate = nil
        isRunning = false
    }

    func reset() {
        timer?.invalidate(); timer = nil
        phase = .idle
        timeRemaining = TimeInterval(workMinutes) * 60
        endDate = nil
        isRunning = false
        completedSessions = 0
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Skip to the end of the current phase immediately.
    func skipPhase() {
        timer?.invalidate(); timer = nil
        phaseDidComplete(silent: true)
    }

    // MARK: - Phase transitions

    private func beginPhase(_ newPhase: Phase) {
        phase = newPhase
        timeRemaining = currentPhaseDuration()
        endDate = Date().addingTimeInterval(timeRemaining)
        scheduleEndNotification(for: newPhase, in: timeRemaining)
        startTicker()
    }

    private func phaseDidComplete(silent: Bool = false) {
        let just = phase
        switch just {
        case .working:
            completedSessions += 1
            let isLong = sessionsBeforeLongBreak > 0
                       && completedSessions % sessionsBeforeLongBreak == 0
            beginPhase(isLong ? .longBreak : .shortBreak)
        case .shortBreak, .longBreak:
            beginPhase(.working)
        case .idle:
            return
        }
    }

    // MARK: - Ticker

    private func startTicker() {
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                guard let end = self.endDate else { return }
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0 {
                    self.timeRemaining = 0
                    timer.invalidate()
                    self.timer = nil
                    self.isRunning = false
                    self.phaseDidComplete()
                } else {
                    self.timeRemaining = remaining
                }
            }
        }
    }

    private func currentPhaseDuration() -> TimeInterval {
        switch phase {
        case .idle, .working: return TimeInterval(workMinutes) * 60
        case .shortBreak:     return TimeInterval(shortBreakMinutes) * 60
        case .longBreak:      return TimeInterval(longBreakMinutes) * 60
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Permission denied or not available; we still run the timer.
        }
    }

    private func scheduleEndNotification(for phase: Phase, in seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        switch phase {
        case .working:
            content.title = "Focus session complete"
            content.body = "Take a break — you've earned it."
        case .shortBreak:
            content.title = "Short break over"
            content.body = "Back to focus when you're ready."
        case .longBreak:
            content.title = "Long break over"
            content.body = "Ready for the next pomodoro?"
        case .idle:
            return
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 0.1), repeats: false)
        let request = UNNotificationRequest(identifier: "pomodoro.\(phase.rawValue)",
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Display helpers

    var phaseTotalDuration: TimeInterval {
        switch phase {
        case .idle, .working: return TimeInterval(workMinutes) * 60
        case .shortBreak:     return TimeInterval(shortBreakMinutes) * 60
        case .longBreak:      return TimeInterval(longBreakMinutes) * 60
        }
    }

    var phaseProgress: Double {
        let total = phaseTotalDuration
        guard total > 0 else { return 0 }
        return 1.0 - timeRemaining / total
    }

    var formattedTime: String {
        let total = Int(ceil(timeRemaining))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
