import SwiftUI

/// Floating diagnostic HUD. Mixes performance metrics with live physics
/// readouts pulled from `Gravitas` (Bardeen / Press-Teukolsky closed forms),
/// plus a collapsible "math" panel listing every closed-form equation the
/// renderer evaluates per pixel.
struct HUDView: View {
    @ObservedObject var params: BlackHoleParameters
    @State private var showMath: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            performanceBlock
            divider
            physicsBlock

            if showMath {
                divider
                MathPanel()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: showMath ? 320 : 220, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.30))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 6)
        .colorScheme(.dark)
        .animation(.easeInOut(duration: 0.18), value: showMath)
    }

    // MARK: - Sections

    private var performanceBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusDot(color: fpsColor(params.fps))
                Text(String(format: "%.0f", params.fps))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                Text("FPS")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.45))
                Spacer(minLength: 8)
                Text(String(format: "%.1f ms", params.frameTimeMs))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showMath.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "function")
                            .font(.system(size: 9, weight: .heavy))
                        Text("EQS")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(1.0)
                    }
                    .foregroundColor(showMath
                        ? Color(red: 0.55, green: 0.95, blue: 1.0)
                        : Color.white.opacity(0.62))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(showMath
                                ? Color(red: 0.20, green: 0.55, blue: 0.85).opacity(0.30)
                                : Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                showMath
                                    ? Color(red: 0.55, green: 0.95, blue: 1.0).opacity(0.55)
                                    : Color.white.opacity(0.14),
                                lineWidth: 0.7
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Tag(text: params.preset.displayName.uppercased(), tone: .accent)
                Tag(text: scaleLabel, tone: scaleTone)
                if params.preset.taaEnabled  { Tag(text: "TAA",   tone: .neutral) }
                if params.preset.bloomEnabled { Tag(text: "BLOOM", tone: .neutral) }
            }
        }
    }

    private var physicsBlock: some View {
        let m = Double(params.mass)
        let s = Double(params.spin)
        let rh   = Gravitas.eventHorizon(mass: m, spin: s * m)
        let rph  = Gravitas.photonSphere(mass: m, spin: s * m)
        let isco = Gravitas.isco(mass: m, spin: s * m, prograde: true)

        return VStack(alignment: .leading, spacing: 3) {
            metricRow(label: "rh",   value: String(format: "%.2f M", rh))
            metricRow(label: "rph",  value: String(format: "%.2f M", rph))
            metricRow(label: "ISCO", value: String(format: "%.2f M", isco))
        }
        .padding(.top, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
            .padding(.top, 8)
    }

    // MARK: - Bits

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.50))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
        }
    }

    private func fpsColor(_ fps: Double) -> Color {
        if fps < 30 { return Color(red: 1.0, green: 0.30, blue: 0.30) }
        if fps < 50 { return Color(red: 1.0, green: 0.78, blue: 0.20) }
        return Color(red: 0.35, green: 0.95, blue: 0.65)
    }

    private var scaleLabel: String {
        String(format: "%d%%", Int((params.effectiveRenderScale * 100).rounded()))
    }

    private var scaleTone: Tag.Tone {
        params.effectiveRenderScale < 0.95 ? .warning : .neutral
    }
}

// MARK: - Math panel
//
// Equations are rendered with SwiftUI AttributedString so subscripts and
// italics look like real math (no LaTeX parser dependency). Each entry shows
// the formula, a one-line description, and the literature reference the
// renderer pulls from. Every formula listed here is evaluated by the GPU
// shader (`BlackHole.metal`) or the CPU bridge (`Bridge/Gravitas.swift`).

private struct MathPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Kerr geometry")
            equation(
                title: "Event horizon",
                formula: eq("r₊ = M + √(M² − a²)"),
                cite: "Bardeen 1973"
            )
            equation(
                title: "Photon sphere",
                formula: eq("r_ph = 2M[1 + cos(⅔ arccos(−a*))]"),
                cite: "Bardeen 1973"
            )
            equation(
                title: "ISCO",
                formula: eq("r_ISCO = M[3 + Z₂ − √((3−Z₁)(3+Z₁+2Z₂))]"),
                cite: "Bardeen, Press & Teukolsky 1972"
            )
            equation(
                title: "Ergosphere",
                formula: eq("r_E(θ) = M + √(M² − a²cos²θ)"),
                cite: "Kerr 1963"
            )

            sectionHeader("Geodesic dynamics")
            equation(
                title: "Kerr-Schild accel",
                formula: eq("a⃗ = −(M/r² + 3M L²eff /r⁴)(σ/r²) r̂ + ω (ŷ × v⃗)"),
                cite: "Chandrasekhar 1983"
            )
            equation(
                title: "Frame-dragging (ZAMO)",
                formula: eq("ω = 2 M a / (r³ + a² r)"),
                cite: "Bardeen, Press & Teukolsky 1972"
            )

            sectionHeader("Accretion disk")
            equation(
                title: "Keplerian ω",
                formula: eq("Ω = sgn(a*)·√M / (r^(3/2) + a √M)"),
                cite: "Page & Thorne 1974"
            )
            equation(
                title: "Doppler factor",
                formula: eq("δ = 1 / [u_t (1 − Ω L_z)]"),
                cite: "Page & Thorne 1974"
            )
            equation(
                title: "Novikov–Thorne T(r)",
                formula: eq("T ∝ T₀ (r_ISCO/r)^(3/4) (1 − √(r_ISCO/r))^(1/4) · δ"),
                cite: "Novikov & Thorne 1973"
            )
            equation(
                title: "Relativistic beaming",
                formula: eq("I_obs = I_em · δ^(7/2)"),
                cite: "Liouville's theorem"
            )

            sectionHeader("Pipeline")
            equation(
                title: "Blackbody (linear)",
                formula: eq("c_lin = (Tanner-Helland(T))^(2.2)"),
                cite: "Tanner-Helland approx."
            )
            equation(
                title: "ACES tonemap",
                formula: eq("c' = clamp((c(2.51c+0.03))/(c(2.43c+0.59)+0.14))"),
                cite: "Narkowicz 2014"
            )
        }
        .padding(.top, 8)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundColor(Color(red: 0.55, green: 0.95, blue: 1.0).opacity(0.85))
            .padding(.top, 6)
    }

    @ViewBuilder
    private func equation(title: String, formula: AttributedString, cite: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text(cite)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.30))
            }
            Text(formula)
                .font(.system(size: 11, design: .serif))
                .foregroundColor(.white.opacity(0.92))
        }
    }
}

/// Build an AttributedString that simulates math typography:
/// `_x` underscore introduces a subscript run; uses italic by default; respects Unicode.
private func eq(_ s: String) -> AttributedString {
    var out = AttributedString()
    var italic = AttributeContainer()
    italic.font = .system(size: 11, design: .serif).italic()

    var sub = AttributeContainer()
    sub.font = .system(size: 8, design: .serif).italic()
    sub.baselineOffset = -2

    var sup = AttributeContainer()
    sup.font = .system(size: 8, design: .serif).italic()
    sup.baselineOffset = 5

    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c == "_", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex {
            // Single-char subscript or {…} group.
            let after = s[next]
            if after == "{" {
                let close = s[next...].firstIndex(of: "}") ?? s.endIndex
                let body = String(s[s.index(after: next)..<close])
                out.append(AttributedString(body).mergingAttributes(sub))
                i = (close < s.endIndex) ? s.index(after: close) : s.endIndex
            } else {
                out.append(AttributedString(String(after)).mergingAttributes(sub))
                i = s.index(after: next)
            }
        } else if c == "^", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex {
            let after = s[next]
            if after == "(" {
                let close = s[next...].firstIndex(of: ")") ?? s.endIndex
                let body = String(s[s.index(after: next)..<close])
                out.append(AttributedString(body).mergingAttributes(sup))
                i = (close < s.endIndex) ? s.index(after: close) : s.endIndex
            } else {
                out.append(AttributedString(String(after)).mergingAttributes(sup))
                i = s.index(after: next)
            }
        } else {
            // Italicize Latin letters but keep punctuation / math symbols upright.
            let ch = String(c)
            if c.isLetter && c.isASCII {
                out.append(AttributedString(ch).mergingAttributes(italic))
            } else {
                out.append(AttributedString(ch))
            }
            i = s.index(after: i)
        }
    }
    return out
}

// MARK: - Sub-components

private struct StatusDot: View {
    let color: Color
    @State private var pulse: Bool = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.7), radius: pulse ? 4 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private struct Tag: View {
    enum Tone { case accent, neutral, warning }
    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(border, lineWidth: 0.6)
            )
    }

    private var foreground: Color {
        switch tone {
        case .accent:  return Color(red: 0.55, green: 0.95, blue: 1.0)
        case .neutral: return .white.opacity(0.78)
        case .warning: return Color(red: 1.0, green: 0.78, blue: 0.20)
        }
    }
    private var background: Color {
        switch tone {
        case .accent:  return Color(red: 0.20, green: 0.55, blue: 0.85).opacity(0.30)
        case .neutral: return .white.opacity(0.06)
        case .warning: return Color(red: 1.0, green: 0.6, blue: 0.10).opacity(0.20)
        }
    }
    private var border: Color {
        switch tone {
        case .accent:  return Color(red: 0.55, green: 0.95, blue: 1.0).opacity(0.40)
        case .neutral: return .white.opacity(0.15)
        case .warning: return Color(red: 1.0, green: 0.78, blue: 0.20).opacity(0.45)
        }
    }
}
