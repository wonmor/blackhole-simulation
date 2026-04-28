import SwiftUI

struct ControlPanel: View {
    @ObservedObject var params: BlackHoleParameters

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Black Hole")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))

            slider("Mass",      value: $params.mass,            range: 0.2...4.0,   format: "%.2f")
            slider("Spin",      value: $params.spin,            range: -1.0...1.0,  format: "%.2f")
            slider("Lensing",   value: $params.lensingStrength, range: 0.0...3.0,   format: "%.2f")

            Divider().background(Color.white.opacity(0.15))

            slider("Disk size",    value: $params.diskSize,    range: 1.0...20.0, format: "%.1f")
            slider("Disk density", value: $params.diskDensity, range: 0.0...3.0,  format: "%.2f")
            slider("Disk temp",    value: $params.diskTemp,    range: 0.2...3.0,  format: "%.2f")

            Divider().background(Color.white.opacity(0.15))

            slider("Zoom",      value: $params.zoom,           range: 3.0...40.0, format: "%.1f")
            stepper("Ray steps", value: $params.maxRaySteps,   range: 64...500, step: 16)

            Toggle("Show redshift", isOn: $params.showRedshift)
                .toggleStyle(.switch)
                .foregroundColor(.white)
        }
        .padding(14)
        .frame(width: 280)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func slider(_ label: String,
                        value: Binding<Float>,
                        range: ClosedRange<Float>,
                        format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.9))
            }
            Slider(value: value, in: range)
                .tint(.cyan)
        }
    }

    @ViewBuilder
    private func stepper(_ label: String,
                         value: Binding<Int>,
                         range: ClosedRange<Int>,
                         step: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.9))
            }
            .labelsHidden()
        }
    }
}
