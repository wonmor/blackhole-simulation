import SwiftUI

struct ControlPanel: View {
    @ObservedObject var params: BlackHoleParameters

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Black Hole")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))

                Picker("Quality", selection: $params.preset) {
                    ForEach(QualityPreset.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    sectionHeader("Geometry")
                    slider("Mass",       value: $params.mass,            range: 0.1...10.0,  format: "%.2f")
                    slider("Spin",       value: $params.spin,            range: -0.99...0.99, format: "%.2f")
                    slider("Lensing",    value: $params.lensingStrength, range: 0.0...2.0,   format: "%.2f")
                    slider("Frame drag", value: $params.frameDragStrength, range: 0.0...2.0, format: "%.2f")
                }

                Group {
                    sectionHeader("Accretion disk")
                    slider("Size (M)",       value: $params.diskSize,        range: 4.0...100.0, format: "%.1f")
                    slider("Density",        value: $params.diskDensity,     range: 0.0...5.0,   format: "%.2f")
                    slider("Temp (K)",       value: $params.diskTemp,        range: 1000.0...50000.0, format: "%.0f")
                    slider("Scale height",   value: $params.diskScaleHeight, range: 0.01...0.30, format: "%.2f")
                }

                Group {
                    sectionHeader("Bloom")
                    slider("Threshold", value: $params.bloomThreshold, range: 0.2...3.0, format: "%.2f")
                    slider("Intensity", value: $params.bloomIntensity, range: 0.0...1.5, format: "%.2f")
                }

                Group {
                    sectionHeader("Camera")
                    slider("Zoom (M)",  value: $params.zoom,     range: 1.5...100.0, format: "%.1f")
                    slider("Auto-spin", value: $params.autoSpin, range: -0.1...0.1,  format: "%.3f")
                }

                Group {
                    sectionHeader("Effects")
                    toggle("Gravitational lensing",   isOn: $params.enableLensing)
                    toggle("Accretion disk",          isOn: $params.enableDisk)
                    toggle("Doppler beaming",         isOn: $params.enableDoppler)
                    toggle("Photon ring",             isOn: $params.enablePhotonGlow)
                    toggle("Stars + nebula",          isOn: $params.enableStars)
                    toggle("Relativistic jets",       isOn: $params.enableJets)
                    toggle("Show redshift overlay",   isOn: $params.showRedshift)
                }
            }
            .padding(14)
        }
        .frame(width: 290)
        .frame(maxHeight: 620)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(.white.opacity(0.5))
            .padding(.top, 4)
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
    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.switch)
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))
    }
}
