import SwiftUI

// MARK: - Liquid Glass palette

enum GlassPalette {
    static let pink = Color(red: 1.0, green: 0.30, blue: 0.50)
    static let violet = Color(red: 0.60, green: 0.38, blue: 1.0)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [pink, violet], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Glass card (frosted panel + specular border)

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Springy press feedback

struct SpringPressStyle: ButtonStyle {
    var scale: CGFloat = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Marquee caption (seamless auto-scroll for long song titles)

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var color: Color = .primary
    var speed: Double = 26   // points per second

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var gap: CGFloat { 40 }
    private var needsScroll: Bool { containerWidth > 0 && textWidth > containerWidth + 2 }
    private var loopLength: CGFloat { textWidth + gap }
    private var loopDuration: Double { Double(loopLength) / max(speed, 1) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                if needsScroll {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        HStack(spacing: gap) {
                            copy
                            copy
                        }
                        .offset(x: -scrollOffset(timeline.date.timeIntervalSinceReferenceDate))
                    }
                } else {
                    copy
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .clipped()
            .onAppear {
                if containerWidth != width { containerWidth = width }
            }
            .onChange(of: geo.size.width) { newValue in
                if containerWidth != newValue { containerWidth = newValue }
            }
        }
    }

    private var copy: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { g -> Color in
                    DispatchQueue.main.async {
                        if textWidth != g.size.width { textWidth = g.size.width }
                    }
                    return Color.clear
                }
            )
    }

    private func scrollOffset(_ t: Double) -> CGFloat {
        guard needsScroll, loopDuration > 0 else { return 0 }
        let phase = t.truncatingRemainder(dividingBy: loopDuration) / loopDuration
        return CGFloat(phase * Double(loopLength))
    }
}

// MARK: - Shimmering title (liquid sheen across the text itself)

struct ShimmerTitle: View {
    let text: String
    var font: Font = .title2.weight(.bold)
    var active: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 0.7) + 1) / 2
            Text(text)
                .font(font)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.72), .white.opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(active ? 0.55 : 0), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: geo.size.width * (phase * 1.7 - 0.85))
                        .blendMode(.overlay)
                    }
                )
                .lineLimit(2)
        }
    }
}

// MARK: - Shine sweep (for hero cards / artwork)

struct Shine: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { geo in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * 0.5) + 1) / 2
                LinearGradient(
                    colors: [.clear, .white.opacity(0.26), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * 0.6)
                .offset(x: geo.size.width * (phase * 1.8 - 0.9))
                .rotationEffect(.degrees(10))
                .blendMode(.overlay)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Pulse glow (breathing colored shadow, e.g. behind artwork)

struct PulseGlow: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = active ? CGFloat(sin(t * 1.6) * 0.5 + 0.5) : CGFloat(0)
            content
                .shadow(
                    color: GlassPalette.violet.opacity(active ? 0.4 + pulse * 0.25 : 0.14),
                    radius: 16 + pulse * 20,
                    x: 0,
                    y: 8
                )
        }
    }
}

extension View {
    func pulseGlow(active: Bool) -> some View {
        modifier(PulseGlow(active: active))
    }
}

// MARK: - Liquid ambience (drifting color blobs behind the player)

struct LiquidAmbience: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let screen = UIScreen.main.bounds
            let amp: CGFloat = active ? 1 : 0.45
            ZStack {
                blob(color: GlassPalette.violet, radius: screen.width * 0.55)
                    .offset(
                        x: screen.width * (-0.20 + 0.16 * CGFloat(sin(t * 0.33)) * amp),
                        y: screen.height * (-0.22 + 0.12 * CGFloat(cos(t * 0.21)) * amp)
                    )
                blob(color: GlassPalette.pink, radius: screen.width * 0.48)
                    .offset(
                        x: screen.width * (0.22 + 0.14 * CGFloat(cos(t * 0.27 + 2)) * amp),
                        y: screen.height * (0.12 + 0.14 * CGFloat(sin(t * 0.24 + 1)) * amp)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .blur(radius: 36)
            .blendMode(.plusLighter)
            .opacity(active ? 0.85 : 0.55)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func blob(color: Color, radius: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.5), color.opacity(0.0)],
                    center: .center,
                    startRadius: radius * 0.1,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
    }
}

// MARK: - Glass slider (gradient fill + glowing thumb)

struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let clamped = CGFloat(min(max(fraction, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 8)

                Capsule()
                    .fill(GlassPalette.accentGradient)
                    .frame(width: max(10, width * clamped), height: 8)
                    .shadow(color: GlassPalette.pink.opacity(0.55), radius: 7, y: 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                    .overlay(Circle().stroke(Color.white.opacity(0.65), lineWidth: 1))
                    .offset(x: width * clamped - 8)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let f = min(max(0, Double(gesture.location.x / width)), 1)
                        value = range.lowerBound + f * span
                        onEditingChanged(true)
                    }
                    .onEnded { gesture in
                        let f = min(max(0, Double(gesture.location.x / width)), 1)
                        value = range.lowerBound + f * span
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 28)
    }
}

// MARK: - Entrance animation (staggered appear)

struct Entrance: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func entrance(delay: Double = 0) -> some View {
        modifier(Entrance(delay: delay))
    }
}
