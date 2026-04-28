import SwiftUI

/// Cross-platform Pomodoro UI.
///
/// Centerpiece is a circular progress ring with the time + phase label
/// inside. Below: Start / Pause / Reset / Skip controls. Settings open
/// a disclosure with the configurable durations.
struct PomodoroView: View {
    @ObservedObject var timer: PomodoroTimer
    @State private var showingSettings: Bool = false

    private let cyan   = Color(red: 0.55, green: 0.95, blue: 1.0)
    private let amber  = Color(red: 1.00, green: 0.78, blue: 0.20)
    private let purple = Color(red: 0.65, green: 0.55, blue: 1.00)

    var body: some View {
        VStack(spacing: 22) {
            ringView
            controls
            stats
            if showingSettings { settings }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
        .frame(minHeight: 460)
        .background(panelBackground)
        .overlay(panelBorder)
        .colorScheme(.dark)
    }

    // MARK: - Ring

    private var ringView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.001, timer.phaseProgress))
                .stroke(
                    AngularGradient(
                        colors: [phaseColor.opacity(0.6), phaseColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: timer.phaseProgress)

            VStack(spacing: 4) {
                Text(timer.formattedTime)
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                Text(timer.phase.label.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(phaseColor)
            }
        }
        .frame(width: 220, height: 220)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                timer.reset()
            } label: {
                ControlIcon(symbol: "arrow.counterclockwise", color: .white.opacity(0.62))
            }
            .buttonStyle(.plain)

            Button {
                if timer.isRunning { timer.pause() } else { timer.start() }
            } label: {
                Text(timer.isRunning ? "Pause" : (timer.phase == .idle ? "Start Focus" : "Resume"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(phaseColor)
                    )
            }
            .buttonStyle(.plain)

            Button {
                timer.skipPhase()
            } label: {
                ControlIcon(symbol: "forward.end.fill", color: .white.opacity(0.62))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats + settings

    private var stats: some View {
        HStack {
            stat(label: "Sessions", value: "\(timer.completedSessions)")
            Divider().frame(height: 24).background(Color.white.opacity(0.08))
            stat(label: "Until long break",
                 value: "\(max(0, timer.sessionsBeforeLongBreak - (timer.completedSessions % timer.sessionsBeforeLongBreak)))")
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "chevron.up" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(7)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            durationStepper("Focus",        binding: $timer.workMinutes,       range: 5...90)
            durationStepper("Short break",  binding: $timer.shortBreakMinutes, range: 1...30)
            durationStepper("Long break",   binding: $timer.longBreakMinutes,  range: 5...60)
            durationStepper("Long break every", binding: $timer.sessionsBeforeLongBreak,
                            range: 2...8, suffix: "sessions")
        }
        .padding(.top, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func durationStepper(_ label: String,
                                 binding: Binding<Int>,
                                 range: ClosedRange<Int>,
                                 suffix: String = "min") -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
            Spacer()
            Stepper(value: binding, in: range) {
                Text("\(binding.wrappedValue) \(suffix)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
            }
            .labelsHidden()
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.white.opacity(0.92))
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: - Cosmetics

    private var phaseColor: Color {
        switch timer.phase {
        case .idle, .working: return cyan
        case .shortBreak:     return amber
        case .longBreak:      return purple
        }
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.30))
        }
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.8
            )
    }
}

private struct ControlIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
            )
    }
}
